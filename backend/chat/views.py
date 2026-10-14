import json
import logging
import os
import re
import socket
import tempfile
import time
import urllib.error
import urllib.request

logger = logging.getLogger(__name__)


class OpenRouterUnavailable(RuntimeError):
    """OpenRouter billing, auth, or rate-limit — video pipeline fallback only."""


class GeminiChatUnavailable(RuntimeError):
    """Gemini chat billing, auth, quota, or network — use offline chat fallback."""

from django.conf import settings as django_settings
from datetime import timedelta

from django.db.models import Count, Max
from django.utils import timezone
from rest_framework import parsers, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .behavior_context import (
    build_chat_charts,
    build_gemini_behavior_system_prompt,
    parse_client_behavior_payload,
)
from .models import UserMentalState, ChatMessage, ChatSession, analyze_uploaded_image_file
from .video_model import analyze_video_file_path
from .serializers import (
    ChatHistorySerializer,
    ChatMessageCreateSerializer,
    ChatRequestSerializer,
    ChatSessionCreateSerializer,
    ChatSessionSerializer,
    OpenRouterProxySerializer,
    UserMentalStateSerializer,
)
from .safety import CRISIS_REPLY, is_crisis_message
from subscriptions.permissions import require_subscription_feature
from subscriptions.services import SubscriptionService

MINDSYNC_SYSTEM_PROMPT = """
You are MindSync AI, an intelligent and compassionate digital psychologist.

Your purpose is to analyze the user's emotional and physical well-being based on their message and behavior patterns.

Core Responsibilities:
- Detect emotional states such as stress, anxiety, sadness, frustration, or mental fatigue
- Identify possible physical symptoms related to digital lifestyle (e.g., headache, eye strain, sleep issues)
- Consider the possibility of excessive screen time or mobile usage as a contributing factor
- Suggest healthy habits including rest and light physical activity when appropriate
- Provide supportive, practical, and safe advice

Empathy Style Rules:
- Do NOT start responses with "I'm sorry to hear that"
- Avoid over-apologizing language
- Instead, acknowledge naturally like:
  - "I understand how you're feeling"
  - "It sounds like you're experiencing..."
  - "I can see that this is affecting you"
- Avoid alarming the user

Smart Analysis Requirement:
If user symptoms include:
- Headache
- Eye pain / strain
- Tiredness / fatigue
- Irritation or lack of focus

Then gently suggest:
- It might be related to prolonged mobile or screen usage
- Recommend reducing screen time, taking breaks, or resting eyes

Response Structure:
1. Acknowledge the user's feelings or symptoms
2. Provide a brief emotional and behavioral analysis
3. Mention possible causes (including screen time if relevant)
4. Suggest practical coping strategies:
   - Eye rest (20-20-20 rule)
   - Break from screen
   - Hydration
   - Relaxation techniques
5. Provide gentle mental health support
6. Ask a soft follow-up question

Tone:
- Human-like
- Supportive and reassuring
- Clear and simple

Safety:
- If signs of severe stress or anxiety appear, suggest seeking professional help politely

Goal:
Help the user feel understood, supported, and guided toward healthier digital and mental habits.
""".strip()


def _fallback_supportive_reply(user_message: str, history_items) -> str:
    text = (user_message or "").strip().lower()
    previous_assistant = [
        item.get("content", "").strip()
        for item in history_items
        if item.get("role") == "assistant" and item.get("content")
    ]
    last_reply = previous_assistant[-1].lower() if previous_assistant else ""

    if any(k in text for k in ("headache", "migraine", "eye strain", "screen time", "tired eyes")):
        options = [
            "That sounds really draining. If you want, try a short 10-minute break, some water, and softer screen brightness.",
            "I hear you — that can feel exhausting. A brief pause away from the screen and a little hydration might help your body reset.",
        ]
    elif any(k in text for k in ("anxious", "anxiety", "panic", "overwhelmed", "stress")):
        options = [
            "That makes a lot of sense, and you're not overreacting. If it helps, take one slow breath and focus only on the next small step.",
            "I'm really sorry this feels so heavy right now. You don't have to fix everything at once — just one gentle step is enough for now.",
        ]
    elif any(k in text for k in ("sad", "lonely", "down", "depressed", "empty")):
        options = [
            "I'm sorry you're feeling this way. What you're carrying sounds painful, and it matters.",
            "That sounds really hard. I'm glad you shared it instead of holding it in alone.",
        ]
    else:
        options = [
            "I hear you. That sounds like a lot to carry right now.",
            "That actually makes a lot of sense. Thanks for sharing that with me.",
        ]

    # Reduce repeated fallback text by switching option when same as last.
    reply = options[0]
    if last_reply and reply.lower() in last_reply and len(options) > 1:
        reply = options[1]

    return _postprocess_reply(reply)


def _postprocess_reply(raw: str) -> str:
    text = (raw or "").strip()
    text = re.sub(r"^\s*Assistant:\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()

    # Keep concise and avoid questionnaire-like responses.
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if len(lines) > 6:
        lines = lines[:6]
    text = "\n".join(lines).strip()

    # At most one question in the final output.
    q_count = text.count("?")
    if q_count > 1:
        first_q = text.find("?")
        text = text[: first_q + 1].strip()
    return text


def _urlopen_with_retries(req: urllib.request.Request, *, attempts: int = 3, timeout: int = 45) -> str:
    last_exc: Exception | None = None
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read().decode('utf-8')
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionResetError, OSError) as exc:
            last_exc = exc
            if attempt < attempts - 1:
                time.sleep(0.6 * (attempt + 1))
                continue
            logger.warning(
                'OpenRouter unreachable after %s attempts (%s); using offline fallback.',
                attempts,
                exc,
            )
            raise OpenRouterUnavailable('network') from exc
    raise OpenRouterUnavailable('network') from last_exc


def _build_gemini_contents(history_items, user_message: str) -> list[dict]:
    contents: list[dict] = []
    for item in history_items[-12:]:
        role = (item.get('role') or '').strip()
        content = (item.get('content') or '').strip()
        if not content:
            continue
        if role == 'user':
            contents.append({'role': 'user', 'parts': [{'text': content[:4000]}]})
        elif role == 'assistant':
            contents.append({'role': 'model', 'parts': [{'text': content[:4000]}]})
    contents.append({'role': 'user', 'parts': [{'text': user_message.strip()[:8000]}]})
    return contents


def _gemini_chat_model_chain() -> list[str]:
    """Primary chat model first, then quota/rate-limit fallbacks (chat-only)."""
    primary = (
        os.environ.get('GEMINI_CHAT_MODEL', '').strip()
        or getattr(django_settings, 'GEMINI_CHAT_MODEL', 'gemini-2.5-flash')
        or 'gemini-2.5-flash'
    )
    fallbacks = getattr(django_settings, 'GEMINI_CHAT_MODEL_FALLBACKS', None) or []
    chain: list[str] = []
    for model in [primary, *fallbacks]:
        name = (model or '').strip()
        if name and name not in chain:
            chain.append(name)
    return chain


def _gemini_generate_once(
    *,
    api_key: str,
    model: str,
    user_message: str,
    history_items,
    system_prompt: str,
) -> str:
    url = (
        f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'
        f'?key={api_key}'
    )
    effective_system = (system_prompt or MINDSYNC_SYSTEM_PROMPT).strip()
    payload = json.dumps(
        {
            'systemInstruction': {'parts': [{'text': effective_system}]},
            'contents': _build_gemini_contents(history_items, user_message),
            'generationConfig': {
                'temperature': float(os.environ.get('GEMINI_CHAT_TEMPERATURE', '0.7') or 0.7),
                'maxOutputTokens': int(os.environ.get('GEMINI_CHAT_MAX_TOKENS', '512') or 512),
            },
        }
    ).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=payload,
        method='POST',
        headers={'Content-Type': 'application/json; charset=utf-8'},
    )
    raw = _urlopen_with_retries(req, attempts=3, timeout=60)
    data = json.loads(raw)
    candidates = data.get('candidates') or []
    if not candidates:
        raise GeminiChatUnavailable('empty_response')
    parts = (candidates[0].get('content') or {}).get('parts') or []
    text_parts = [p.get('text', '') for p in parts if isinstance(p, dict) and p.get('text')]
    reply = ''.join(text_parts).strip()
    if not reply:
        raise GeminiChatUnavailable('empty_text')
    return _postprocess_reply(reply)


def _generate_gemini_chat_reply(
    user_message: str,
    history_items,
    *,
    system_prompt: str | None = None,
) -> str:
    """Digital Psychologist chat — Google Gemini only (not used for video analysis)."""
    api_key = (getattr(django_settings, 'GEMINI_API_KEY', None) or '').strip()
    if not api_key:
        raise GeminiChatUnavailable('not_configured')

    models = _gemini_chat_model_chain()
    effective_system = (system_prompt or MINDSYNC_SYSTEM_PROMPT).strip()
    last_rate_limit: urllib.error.HTTPError | None = None

    for idx, model in enumerate(models):
        try:
            reply = _gemini_generate_once(
                api_key=api_key,
                model=model,
                user_message=user_message,
                history_items=history_items,
                system_prompt=effective_system,
            )
            if idx > 0:
                logger.info(
                    'Gemini chat succeeded on fallback model %s after primary quota/limit.',
                    model,
                )
            return reply
        except urllib.error.HTTPError as exc:
            code = exc.code
            body = exc.read().decode('utf-8', errors='replace')[:400]
            if code == 429:
                last_rate_limit = exc
                has_next = idx + 1 < len(models)
                logger.warning(
                    'Gemini chat rate limited on %s (HTTP 429)%s.',
                    model,
                    '; trying fallback model' if has_next else '; no fallbacks left',
                )
                if has_next:
                    continue
                raise GeminiChatUnavailable('rate_limited') from exc
            if code in (401, 403):
                logger.warning('Gemini chat auth failed (HTTP %s); using offline fallback.', code)
                raise GeminiChatUnavailable(f'auth_{code}') from exc
            if code == 400:
                logger.warning('Gemini chat bad request (HTTP 400): %s', body[:200])
                raise GeminiChatUnavailable('bad_request') from exc
            logger.warning('Gemini chat HTTP %s: %s', code, body[:200])
            raise GeminiChatUnavailable(f'http_{code}') from exc
        except OpenRouterUnavailable as exc:
            raise GeminiChatUnavailable('network') from exc
        except GeminiChatUnavailable:
            raise
        except Exception as exc:
            logger.warning('Gemini chat error on model %s: %s', model, exc)
            if idx + 1 < len(models):
                continue
            raise GeminiChatUnavailable('network') from exc

    if last_rate_limit is not None:
        raise GeminiChatUnavailable('rate_limited') from last_rate_limit
    raise GeminiChatUnavailable('empty_response')


def _generate_openrouter_reply(user_message: str, history_items) -> str:
    api_key = (getattr(django_settings, 'OPENROUTER_API_KEY', None) or '').strip()
    if not api_key:
        raise OpenRouterUnavailable('not_configured')

    model = (
        os.environ.get('MINDSYNC_MODEL', '').strip()
        or os.environ.get('OPENROUTER_MODEL', '').strip()
        or 'openai/gpt-3.5-turbo'
    )

    cleaned_history = []
    for item in history_items[-20:]:
        role = (item.get('role') or '').strip()
        content = (item.get('content') or '').strip()
        if role not in ('user', 'assistant') or not content:
            continue
        cleaned_history.append({'role': role, 'content': content[:4000]})

    messages = [{'role': 'system', 'content': MINDSYNC_SYSTEM_PROMPT}]
    messages.extend(cleaned_history[-12:])
    messages.append({'role': 'user', 'content': user_message.strip()[:8000]})

    payload = json.dumps({'model': model, 'messages': messages}).encode('utf-8')
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions',
        data=payload,
        method='POST',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json; charset=utf-8',
            'User-Agent': 'MindSync/1.0',
            'HTTP-Referer': getattr(django_settings, 'OPENROUTER_REFERER', 'http://localhost'),
            'X-Title': getattr(django_settings, 'OPENROUTER_TITLE', 'MindSync'),
        },
    )
    try:
        raw = _urlopen_with_retries(req)
    except urllib.error.HTTPError as exc:
        code = exc.code
        if code == 402:
            logger.warning(
                'OpenRouter HTTP 402 (insufficient credits on this API key account). '
                'Key in backend/.env is accepted but the OpenRouter wallet is empty — '
                'add credits at https://openrouter.ai/settings/credits then restart runserver. '
                'Using offline fallback.',
            )
            raise OpenRouterUnavailable('payment_required') from exc
        if code in (401, 403):
            logger.warning('OpenRouter auth failed (HTTP %s); using offline fallback.', code)
            raise OpenRouterUnavailable(f'auth_{code}') from exc
        if code == 429:
            logger.warning('OpenRouter rate limited (HTTP 429); using offline fallback.')
            raise OpenRouterUnavailable('rate_limited') from exc
        raise
    except OpenRouterUnavailable:
        raise

    data = json.loads(raw)
    reply = data['choices'][0]['message']['content']
    return _postprocess_reply(reply or '')


class AnalyzeImageAPIView(APIView):
    """
    POST /api/analyze-image/
    multipart field: image
    """

    permission_classes = (AllowAny,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "image" not in request.data:
            return Response(
                {"status": "error", "detail": "No image file provided (field name: image)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            prediction, confidence = analyze_uploaded_image_file(request.data["image"])
            return Response(
                {
                    "status": "success",
                    "prediction": prediction,
                    "confidence": round(float(confidence), 4),
                }
            )
        except Exception as exc:
            logger.exception("analyze-image failed")
            return Response(
                {"status": "error", "detail": str(exc)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class AnalyzeVideoAPIView(APIView):
    """
    POST /api/analyze-video/
    multipart field: video
    """

    permission_classes = (AllowAny,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "video" not in request.data:
            return Response(
                {"status": "error", "detail": "No video file provided (field name: video)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        video_file = request.data["video"]
        suffix = ".mp4"
        name = getattr(video_file, "name", "") or ""
        lower = name.lower()
        if lower.endswith(".mov"):
            suffix = ".mov"
        elif lower.endswith(".webm"):
            suffix = ".webm"

        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                for chunk in video_file.chunks():
                    tmp.write(chunk)
                tmp_path = tmp.name
            result = analyze_video_file_path(tmp_path)
            return Response({"status": "success", **result})
        except Exception as exc:
            logger.exception("analyze-video failed")
            return Response(
                {"status": "error", "detail": str(exc)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass


class MentalStateAPIView(APIView):
    """GET/PATCH mental context used for chat personalization."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        try:
            state = request.user.mental_state
        except UserMentalState.DoesNotExist:
            return Response(
                {'error': 'mental_state_not_found', 'detail': 'No mental state profile exists for this user.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(UserMentalStateSerializer(state).data)

    def patch(self, request):
        try:
            state = request.user.mental_state
        except UserMentalState.DoesNotExist:
            state = UserMentalState(user=request.user)

        serializer = UserMentalStateSerializer(state, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save(user=request.user)
        return Response(UserMentalStateSerializer(state).data, status=status.HTTP_200_OK)


class ChatAPIView(APIView):
    """
    POST /api/chat/

    Body: {"message": "..."}
    Returns: {"reply": "..."}
    """

    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'chat_digital_psychologist',
        'Upgrade to Premium to access Digital Psychologist chat.',
    )
    def post(self, request):
        ser = ChatRequestSerializer(data=request.data)
        if not ser.is_valid():
            return Response(
                {'error': 'validation_error', 'detail': ser.errors},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user_message = ser.validated_data['message']
        history = ser.validated_data.get('history', [])
        session_id = ser.validated_data.get('session_id')
        client_behavior = parse_client_behavior_payload(
            ser.validated_data.get('behavior_context'),
        )

        UserMentalState.objects.get_or_create(user=request.user)
        try:
            from users.services.mental_state_sync import sync_user_mental_state

            sync_user_mental_state(request.user)
        except Exception:
            logger.exception('Failed to sync mental state before chat reply.')

        behavior_system_prompt = build_gemini_behavior_system_prompt(
            request.user,
            client_behavior,
            base_prompt=MINDSYNC_SYSTEM_PROMPT,
        )

        if session_id:
            session = ChatSession.objects.filter(user=request.user, id=session_id).first()
            if session is None:
                return Response(
                    {'error': 'session_not_found', 'detail': 'Chat session was not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )
        else:
            session = ChatSession.objects.create(user=request.user, title='New chat')

        # Fallback to recent persisted history when client doesn't send it.
        if not history:
            last_qs = ChatMessage.objects.filter(user=request.user).order_by('-created_at')[:6]
            last_rows = list(reversed(list(last_qs)))
            history = []
            for row in last_rows:
                history.append({"role": "user", "content": row.message.strip()})
                history.append({"role": "assistant", "content": row.response.strip()})

        if is_crisis_message(user_message):
            reply = CRISIS_REPLY
        elif os.environ.get('GEMINI_USE_FALLBACK', '').strip().lower() in {
            '1',
            'true',
            'yes',
        } or os.environ.get('OPENROUTER_USE_FALLBACK', '').strip().lower() in {
            '1',
            'true',
            'yes',
        }:
            reply = _fallback_supportive_reply(
                user_message=user_message,
                history_items=history,
            )
        else:
            try:
                reply = _generate_gemini_chat_reply(
                    user_message=user_message,
                    history_items=history,
                    system_prompt=behavior_system_prompt,
                )
            except GeminiChatUnavailable as exc:
                reason = str(exc) or 'unavailable'
                if reason not in ('not_configured',):
                    logger.info('Gemini chat fallback (%s) for chat reply.', reason)
                reply = _fallback_supportive_reply(
                    user_message=user_message,
                    history_items=history,
                )
            except Exception:
                logger.exception('Gemini chat failed unexpectedly; using fallback reply.')
                reply = _fallback_supportive_reply(
                    user_message=user_message,
                    history_items=history,
                )

        if not reply:
            return Response(
                {'error': 'empty_reply', 'detail': 'No reply could be generated.'},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        ChatMessage.objects.create(
            user=request.user,
            session=session,
            message=user_message,
            response=reply,
        )

        charts = build_chat_charts(
            request.user,
            client_behavior,
            user_message=user_message,
        )

        return Response(
            {'reply': reply, 'session_id': session.id, 'charts': charts},
            status=status.HTTP_200_OK,
        )


class ChatHistoryAPIView(APIView):
    """
    GET /api/chat/history/

    Returns saved turns for the authenticated user (same rows as DB; survives logout/login).
    Optional: ?limit=200 (default 500, max 1000).
    """

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        session_id = request.query_params.get('session_id')
        try:
            limit = int(request.query_params.get('limit', '500'))
        except ValueError:
            limit = 500
        limit = max(1, min(limit, 1000))

        qs = ChatMessage.objects.filter(user=request.user)
        if session_id:
            qs = qs.filter(session_id=session_id)
        qs = qs.order_by('created_at')[:limit]
        data = ChatHistorySerializer(qs, many=True).data
        return Response({'count': len(data), 'results': data}, status=status.HTTP_200_OK)


def _purge_chat_sessions_older_than_days(user, days: int = 7) -> int:
    cutoff = timezone.now() - timedelta(days=days)
    qs = ChatSession.objects.filter(user=user, updated_at__lt=cutoff)
    count, _ = qs.delete()
    return count


class ChatSessionListCreateAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        _purge_chat_sessions_older_than_days(request.user, days=7)
        sessions = (
            ChatSession.objects.filter(user=request.user)
            .annotate(turns=Count('messages'), last_message_at=Max('messages__created_at'))
            .order_by('-updated_at')
        )
        return Response({'results': ChatSessionSerializer(sessions, many=True).data}, status=status.HTTP_200_OK)

    def post(self, request):
        ser = ChatSessionCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        session = ChatSession.objects.create(
            user=request.user,
            title=ser.validated_data.get('title') or 'New chat',
        )
        data = ChatSessionSerializer(session).data
        data['turns'] = 0
        return Response(data, status=status.HTTP_201_CREATED)


class ChatSessionDeleteAPIView(APIView):
    """Permanently delete one chat session and all its messages."""

    permission_classes = (IsAuthenticated,)

    def delete(self, request, session_id: int):
        session = ChatSession.objects.filter(user=request.user, id=session_id).first()
        if session is None:
            return Response(
                {'error': 'session_not_found', 'detail': 'Chat session was not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        session.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ChatSessionMessagesAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request, session_id: int):
        session = ChatSession.objects.filter(user=request.user, id=session_id).first()
        if session is None:
            return Response(
                {'error': 'session_not_found', 'detail': 'Chat session was not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        qs = session.messages.order_by('created_at')
        data = ChatHistorySerializer(qs, many=True).data
        return Response({'session_id': session.id, 'title': session.title, 'results': data}, status=status.HTTP_200_OK)

    def post(self, request, session_id: int):
        if not request.user or not request.user.is_authenticated:
            return Response(
                {'message': 'Authentication required.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        if not SubscriptionService.can_access_feature(request.user, 'chat_digital_psychologist'):
            return Response(
                {
                    'message': 'Upgrade your plan to access this feature.',
                    'detail': 'Digital Psychologist chat is available in Standard and Premium plans.',
                },
                status=status.HTTP_403_FORBIDDEN,
            )
        session = ChatSession.objects.filter(user=request.user, id=session_id).first()
        if session is None:
            return Response(
                {'error': 'session_not_found', 'detail': 'Chat session was not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        ser = ChatMessageCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        row = ChatMessage.objects.create(
            user=request.user,
            session=session,
            message=ser.validated_data['message'],
            response=ser.validated_data['response'],
        )
        data = ChatHistorySerializer(row).data
        return Response(data, status=status.HTTP_201_CREATED)


class OpenRouterProxyAPIView(APIView):
    """
    POST /api/chat/openrouter/

    Legacy route name — forwards chat to Google Gemini server-side (CORS-safe for web clients).
    Body: {"model": "...", "messages": [{"role":"system|user|assistant","content":"..."}, ...]}
    Returns: {"reply": "..."}
    """

    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'chat_digital_psychologist',
        'Upgrade to Premium to access Digital Psychologist chat.',
    )
    def post(self, request):
        ser = OpenRouterProxySerializer(data=request.data)
        if not ser.is_valid():
            return Response(
                {'error': 'validation_error', 'detail': ser.errors},
                status=status.HTTP_400_BAD_REQUEST,
            )

        messages = ser.validated_data['messages']
        history: list[dict] = []
        user_message = ''
        for msg in messages:
            role = (msg.get('role') or '').strip()
            content = (msg.get('content') or '').strip()
            if role == 'system' or not content:
                continue
            if role == 'user':
                user_message = content
                history.append({'role': 'user', 'content': content})
            elif role == 'assistant':
                history.append({'role': 'assistant', 'content': content})

        if not user_message and history:
            last = history[-1]
            if last.get('role') == 'user':
                user_message = last.get('content', '')

        if not user_message:
            return Response(
                {'error': 'validation_error', 'detail': 'At least one user message is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        prior = history[:-1] if history and history[-1].get('role') == 'user' else history

        try:
            reply = _generate_gemini_chat_reply(user_message, prior)
        except GeminiChatUnavailable as exc:
            return Response(
                {
                    'error': 'gemini_chat_unavailable',
                    'detail': str(exc),
                },
                status=status.HTTP_502_BAD_GATEWAY,
            )
        except Exception as exc:
            logger.exception('Gemini proxy chat failed')
            return Response(
                {'error': 'gemini_chat_error', 'detail': str(exc)},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        return Response({'reply': reply}, status=status.HTTP_200_OK)
