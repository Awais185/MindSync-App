from __future__ import annotations

import base64
import json
import logging
import math
import os
import re
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import cv2
from django.conf import settings
from django.db import close_old_connections
from django.utils import timezone

from tracking.models import VideoClip
from tracking.services.behavior_analysis import analyze_and_update_video_chunk, predict_behavior_from_text
from users.models import VideoChunkAnalysis

logger = logging.getLogger(__name__)

_ANALYSIS_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix='video-analysis')

VISION_PROMPT = (
    "You are a facial expression analyst and behavior observer for MindSync. "
    "Analyse this frame and describe facial expression, activities happening, and any unusual things you notice. "
    "Include human behaviour, mood, expressions, and activities. "
    "Keep the response concise, under 100 words, and prioritise human behaviour and emotions over scene description."
)

CONTENT_LABELS = [
    # 1) Negative mental health states
    "Stress",
    "Anxiety",
    "Depression",
    "Burnout",
    "Hopelessness",
    "Loneliness",
    "Overthinking",
    "Fear / Panic",
    "Anger / Irritability",
    "Frustration",
    "Emotional exhaustion",
    # 2) Neutral / stable states
    "Neutral",
    "Calm",
    "Balanced mood",
    "Stable emotional state",
    "Indifferent / no strong emotion",
    # 3) Positive mental states
    "Happiness",
    "Joy",
    "Excitement",
    "Gratitude",
    "Motivation",
    "Confidence",
    "Hopefulness",
    "Relaxation",
    "Peacefulness",
    "Satisfaction",
    "Optimism",
    # 4) Creative / expressive states
    "Poetry / poetic expression",
    "Artistic expression",
    "Deep thinking / philosophical mood",
    "Reflective / self-introspection",
    "Emotional storytelling",
    "Inspirational content",
    "Diary-style expression",
    "Creative sadness (melancholy art/poetry)",
    # 5) Behavioral / cognitive states
    "Social withdrawal",
    "Addiction behavior (social media overuse)",
    "Sleep disturbance pattern",
    "Attention fragmentation",
    "Low engagement behavior",
    "Mood instability",
    "Impulsivity",
    # 6) Crisis / high-risk indicators
    "Suicidal ideation signals",
    "Self-harm related content",
    "Extreme hopelessness",
    "Severe depression indicators",
    "Panic attacks",
    "Psychological distress escalation",
]

DEFAULT_CONTENT_TYPE = {
    "labels": ["Neutral"],
    "main_emotion": "Neutral",
    "sentiment_score": 50,
    "mental_health_score": 0,
    "toxicity_score": 0,
    "risk_score": 0,
    "summary": "No clear signal detected",
}


def _text_present(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_missing_json(value: Any) -> bool:
    return not isinstance(value, dict) or not value


def _requires_reprocessing(clip: VideoClip, analysis_row: VideoChunkAnalysis | None) -> bool:
    # Full rerun is expensive: use it only when upstream artifacts are missing.
    # If only behavior/confidence is missing, we reuse script and run behavior model directly.
    if not _text_present(clip.script_text):
        return True
    if _is_missing_json(clip.content_type):
        return True
    if analysis_row is None:
        return True
    if not _text_present(analysis_row.script_text):
        return True
    if _is_missing_json(analysis_row.content_type):
        return True
    return False


def _clip_chunk_id(clip: VideoClip) -> str:
    return f'clip-{clip.id}'


def _clip_session_id(clip: VideoClip) -> str:
    stamp = int((clip.client_timestamp or clip.created_at).timestamp())
    return f'user-{clip.user_id}-{stamp // 30}'


def _client_created_at_ms(clip: VideoClip) -> int | None:
    ts = clip.client_timestamp or clip.created_at
    if not ts:
        return None
    return int(ts.timestamp() * 1000)


def _openrouter_request(
    *,
    model: str,
    messages: list[dict[str, Any]],
    max_tokens: int,
    temperature: float | None = None,
) -> dict[str, Any]:
    api_key = (getattr(settings, 'OPENROUTER_API_KEY', None) or '').strip()
    if not api_key:
        raise RuntimeError('OPENROUTER_API_KEY is not configured.')

    payload: dict[str, Any] = {
        'model': model,
        'messages': messages,
        'max_tokens': max_tokens,
    }
    if temperature is not None:
        payload['temperature'] = temperature

    body = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions',
        data=body,
        method='POST',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json; charset=utf-8',
            'HTTP-Referer': getattr(settings, 'OPENROUTER_REFERER', 'http://localhost'),
            'X-Title': getattr(settings, 'OPENROUTER_TITLE', 'MindSync'),
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode('utf-8')
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode('utf-8', errors='replace') if exc.fp else str(exc)
        raise RuntimeError(f'OpenRouter HTTP {exc.code}: {detail[:600]}') from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f'OpenRouter unreachable: {exc.reason}') from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f'Invalid OpenRouter JSON: {raw[:300]}') from exc


def _extract_frames_base64(
    video_path: str,
    *,
    start_seconds: float = 0.0,
    end_seconds: float | None = None,
    interval_seconds: int = 5,
    max_frames: int = 12,
) -> list[str]:
    frames: list[str] = []
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return frames

    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    if fps <= 0:
        fps = 30
    frame_interval = max(1, int(fps * interval_seconds))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    start_frame = max(0, int(start_seconds * fps))
    end_frame = total_frames if end_seconds is None else min(total_frames, int(end_seconds * fps))
    if start_frame >= end_frame:
        cap.release()
        return frames
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    current_frame = start_frame
    try:
        while cap.isOpened() and len(frames) < max_frames and current_frame < end_frame:
            success, frame = cap.read()
            if not success:
                break
            if (current_frame - start_frame) % frame_interval == 0:
                ok, buffer = cv2.imencode('.jpg', frame)
                if ok:
                    frames.append(base64.b64encode(buffer.tobytes()).decode('utf-8'))
            current_frame += 1
    finally:
        cap.release()
    return frames


def _generate_script_for_frames(frames: list[str]) -> tuple[list[str], list[str]]:
    vision_model = os.environ.get('OPENROUTER_VISION_MODEL', 'openrouter/auto').strip() or 'openrouter/auto'
    if not frames:
        return [], []

    api_key = (getattr(settings, 'OPENROUTER_API_KEY', None) or '').strip()
    if not api_key:
        return (
            [
                '[Vision unavailable] Configure OPENROUTER_API_KEY on the server to enable frame descriptions.'
                f' Frame {idx + 1}.'
                for idx in range(len(frames))
            ],
            ['offline'] * len(frames),
        )

    responses: list[str] = []
    models_used: list[str] = []
    for frame in frames:
        try:
            response = _openrouter_request(
                model=vision_model,
                messages=[
                    {
                        'role': 'user',
                        'content': [
                            {'type': 'text', 'text': VISION_PROMPT},
                            {
                                'type': 'image_url',
                                'image_url': {
                                    'url': f'data:image/jpeg;base64,{frame}',
                                },
                            },
                        ],
                    }
                ],
                max_tokens=500,
            )
        except Exception as exc:
            logger.warning('Vision frame skipped: %s', exc)
            responses.append('[Frame analysis skipped due to upstream error.]')
            models_used.append('error')
            continue
        content = (
            response.get('choices', [{}])[0]
            .get('message', {})
            .get('content')
        )
        text = content.strip() if isinstance(content, str) and content.strip() else '[No description generated]'
        responses.append(text)
        model_name = response.get('model')
        models_used.append(model_name if isinstance(model_name, str) and model_name else vision_model)
    return responses, models_used


def _generate_script_from_video(video_path: str) -> tuple[str, list[str]]:
    frames = _extract_frames_base64(video_path)
    if not frames:
        raise RuntimeError('No frames could be extracted from the uploaded video clip.')
    responses, models_used = _generate_script_for_frames(frames)
    combined = '\n\n'.join(f'Frame {idx + 1} (Model: {models_used[idx]}):\n{desc}' for idx, desc in enumerate(responses))
    return combined, models_used


def _generate_chunked_scripts(video_path: str, *, chunk_seconds: int = 30) -> list[dict[str, Any]]:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    cap.release()
    if total_frames <= 0:
        return []
    duration_seconds = max(1.0, total_frames / fps)
    total_chunks = max(1, int(math.ceil(duration_seconds / chunk_seconds)))
    chunks: list[dict[str, Any]] = []
    for idx in range(total_chunks):
        start_s = idx * chunk_seconds
        end_s = min(duration_seconds, (idx + 1) * chunk_seconds)
        frames = _extract_frames_base64(
            video_path,
            start_seconds=float(start_s),
            end_seconds=float(end_s),
            interval_seconds=5,
            max_frames=6,
        )
        if not frames:
            continue
        frame_scripts, models_used = _generate_script_for_frames(frames)
        if not frame_scripts:
            continue
        chunk_script = '\n\n'.join(
            f'Frame {frame_idx + 1} (Model: {models_used[frame_idx]}):\n{text}'
            for frame_idx, text in enumerate(frame_scripts)
        )
        chunks.append(
            {
                'chunk_index': idx,
                'start_seconds': int(start_s),
                'end_seconds': int(end_s),
                'frame_scripts': frame_scripts,
                'models_used': models_used,
                'chunk_script': chunk_script,
            }
        )
    return chunks


def _classify_script(script_text: str) -> dict[str, Any]:
    classifier_model = (
        os.environ.get('OPENROUTER_CONTENT_MODEL', 'openai/gpt-4o-mini').strip()
        or 'openai/gpt-4o-mini'
    )
    prompt = f"""
You are an expert AI psychologist and moderation system for MindSync.

Analyze user content deeply.

Detect:
1. Emotion
2. Toxicity
3. Mental health signals
4. Dangerous risk
5. Hidden depression or anxiety wording
6. Stressful language
7. Positive or negative influence

Return ONLY valid JSON:

{{
  "labels": ["label1", "label2"],
  "main_emotion": "emotion",
  "sentiment_score": 0,
  "mental_health_score": 0,
  "toxicity_score": 0,
  "risk_score": 0,
  "summary": "short analysis"
}}

Allowed labels only:
{CONTENT_LABELS}

Rules:
- Multiple labels allowed
- If sadness and stress both exist, include both relevant labels
- If depression wording is found, include Depression or Severe depression indicators (based on severity)
- If worry, fear, or panic is found, include Anxiety and/or Fear / Panic
- If exhausted or life-pressure wording is found, include Stress, Burnout, or Emotional exhaustion
- If crisis cues appear (self-harm, suicidal, severe hopelessness), include crisis labels explicitly
- If no strong signal exists, use Neutral
- JSON only

TEXT:
\"\"\"{script_text}\"\"\"
""".strip()

    api_key = (getattr(settings, 'OPENROUTER_API_KEY', None) or '').strip()
    if not api_key:
        return dict(DEFAULT_CONTENT_TYPE)

    try:
        response = _openrouter_request(
            model=classifier_model,
            messages=[{'role': 'user', 'content': prompt}],
            max_tokens=600,
            temperature=0.1,
        )
    except Exception as exc:
        logger.warning('Content classification skipped: %s', exc)
        out = dict(DEFAULT_CONTENT_TYPE)
        out['summary'] = f'Classifier unavailable: {str(exc)[:120]}'
        return out

    raw = (
        response.get('choices', [{}])[0]
        .get('message', {})
        .get('content', '')
    )
    if not isinstance(raw, str):
        return dict(DEFAULT_CONTENT_TYPE)

    try:
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if not match:
            return dict(DEFAULT_CONTENT_TYPE)
        parsed = json.loads(match.group())
    except Exception:
        parsed = dict(DEFAULT_CONTENT_TYPE)

    labels = parsed.get('labels')
    if not isinstance(labels, list) or not labels:
        parsed['labels'] = ['Neutral']
    else:
        parsed['labels'] = [str(label) for label in labels if str(label) in CONTENT_LABELS] or ['Neutral']
    parsed.setdefault('main_emotion', 'Neutral')
    parsed.setdefault('sentiment_score', 50)
    parsed.setdefault('mental_health_score', 0)
    parsed.setdefault('toxicity_score', 0)
    parsed.setdefault('risk_score', 0)
    parsed.setdefault('summary', 'No clear signal detected')
    return parsed


def _aggregate_per_script_results(results: list[dict[str, Any]]) -> dict[str, Any]:
    if not results:
        return {
            'final_behavior_result': '',
            'final_confidence_score': 0.0,
            'content_analysis_result': dict(DEFAULT_CONTENT_TYPE),
            'frame_summary': [],
            'final_script': '',
            'classification_outputs': {'frame_count': 0, 'aggregated': True},
        }

    behaviors = [str(item.get('behavior_result') or '') for item in results if _text_present(item.get('behavior_result'))]
    confidences = [float(item.get('confidence_score') or 0.0) for item in results]
    counts = Counter(behaviors)
    majority_label = counts.most_common(1)[0][0] if counts else ''
    highest = max(results, key=lambda item: float(item.get('confidence_score') or 0.0))
    highest_label = str(highest.get('behavior_result') or '')
    highest_conf = float(highest.get('confidence_score') or 0.0)
    avg_conf = sum(confidences) / len(confidences) if confidences else 0.0
    tie_for_majority = bool(counts) and list(counts.values()).count(max(counts.values())) > 1
    low_confidence = avg_conf < 0.45
    final_label = highest_label if tie_for_majority or low_confidence or not majority_label else majority_label

    numeric_keys = ['sentiment_score', 'mental_health_score', 'toxicity_score', 'risk_score']
    averaged_content: dict[str, Any] = {}
    for key in numeric_keys:
        vals = []
        for item in results:
            content = item.get('content_type') or {}
            if isinstance(content, dict):
                try:
                    vals.append(float(content.get(key)))
                except Exception:
                    pass
        averaged_content[key] = round(sum(vals) / len(vals), 2) if vals else DEFAULT_CONTENT_TYPE[key]

    emotion_counter = Counter()
    label_counter = Counter()
    for item in results:
        content = item.get('content_type') or {}
        if isinstance(content, dict):
            emotion = str(content.get('main_emotion') or '').strip()
            if emotion:
                emotion_counter[emotion] += 1
            labels = content.get('labels')
            if isinstance(labels, list):
                for label in labels:
                    text = str(label).strip()
                    if text:
                        label_counter[text] += 1

    top_labels = [label for label, _ in label_counter.most_common(5)] or ['Neutral']
    main_emotion = emotion_counter.most_common(1)[0][0] if emotion_counter else 'Neutral'

    final_script = '\n\n'.join(
        f'Chunk {int(item.get("chunk_index", 0)) + 1} Frame {int(item.get("frame_index", 0)) + 1}:\n{item.get("script_text")}'
        for item in results
        if _text_present(item.get('script_text'))
    )
    if not final_script.strip():
        final_script = str(highest.get('script_text') or '')

    content_analysis = {
        'labels': top_labels,
        'main_emotion': main_emotion,
        'sentiment_score': averaged_content['sentiment_score'],
        'mental_health_score': averaged_content['mental_health_score'],
        'toxicity_score': averaged_content['toxicity_score'],
        'risk_score': averaged_content['risk_score'],
        'summary': f'Aggregated from {len(results)} frame-level script analyses.',
    }
    return {
        'final_behavior_result': final_label,
        'final_confidence_score': round(avg_conf, 4),
        'content_analysis_result': content_analysis,
        'frame_summary': results,
        'final_script': final_script,
        'classification_outputs': {
            'aggregated': True,
            'voting': {
                'behavior_vote_counts': dict(counts),
                'tie_for_majority': tie_for_majority,
                'low_confidence_fallback': low_confidence,
                'highest_confidence_label': highest_label,
                'highest_confidence_score': round(highest_conf, 4),
                'selected_label': final_label,
            },
            'frame_count': len(results),
        },
    }


def _run_consolidated_pipeline(video_path: str) -> dict[str, Any]:
    chunk_outputs = _generate_chunked_scripts(video_path, chunk_seconds=30)
    if not chunk_outputs:
        script_text, _ = _generate_script_from_video(video_path)
        behavior = predict_behavior_from_text(script_text)
        content = _classify_script(script_text)
        frame_summary = [
            {
                'chunk_index': 0,
                'frame_index': 0,
                'script_text': script_text,
                'behavior_result': behavior.get('behavior_result'),
                'confidence_score': behavior.get('confidence_score'),
                'content_type': content,
                'classification_outputs': behavior.get('classification_outputs') or {},
            }
        ]
        agg = _aggregate_per_script_results(frame_summary)
        return agg

    per_script_results: list[dict[str, Any]] = []
    for chunk in chunk_outputs:
        chunk_index = int(chunk.get('chunk_index') or 0)
        frame_scripts = chunk.get('frame_scripts') or []
        for frame_index, script_text in enumerate(frame_scripts):
            behavior = predict_behavior_from_text(str(script_text))
            content = _classify_script(str(script_text))
            per_script_results.append(
                {
                    'chunk_index': chunk_index,
                    'frame_index': frame_index,
                    'script_text': str(script_text),
                    'behavior_result': behavior.get('behavior_result'),
                    'confidence_score': behavior.get('confidence_score'),
                    'content_type': content,
                    'classification_outputs': behavior.get('classification_outputs') or {},
                }
            )
    return _aggregate_per_script_results(per_script_results)


def _analyze_video_clip_sync(clip_id: int) -> None:
    close_old_connections()
    try:
        clip = VideoClip.objects.filter(id=clip_id).first()
        if clip is None:
            return

        clip.analysis_status = VideoClip.STATUS_PROCESSING
        clip.analysis_error = ''
        clip.save(update_fields=['analysis_status', 'analysis_error'])

        aggregated = _run_consolidated_pipeline(clip.file.path)
        script_text = str(aggregated.get('final_script') or '')
        content_type = aggregated.get('content_analysis_result') or {}
        behavior_result = str(aggregated.get('final_behavior_result') or '')
        confidence_score = float(aggregated.get('final_confidence_score') or 0.0)
        classification_outputs = aggregated.get('classification_outputs') or {}
        classification_outputs['frame_summary'] = aggregated.get('frame_summary') or []

        clip.script_text = script_text
        clip.content_type = content_type
        clip.analysis_status = VideoClip.STATUS_COMPLETED
        clip.processed_at = timezone.now()
        clip.analysis_error = ''
        clip.save(
            update_fields=[
                'script_text',
                'content_type',
                'analysis_status',
                'processed_at',
                'analysis_error',
            ]
        )
        analysis_row, _ = VideoChunkAnalysis.objects.update_or_create(
            source_clip=clip,
            defaults={
                'user': clip.user,
                'chunk_id': _clip_chunk_id(clip),
                'session_id': _clip_session_id(clip),
                'script_text': script_text,
                'platform': clip.platform,
                'duration_seconds': clip.duration_seconds,
                'source_package': clip.source_package,
                'content_type': content_type,
                'client_created_at_ms': _client_created_at_ms(clip),
                'behavior_result': behavior_result,
                'behavior_results': {
                    'behavior_result': behavior_result,
                    'confidence_score': confidence_score,
                    'classification_outputs': classification_outputs,
                },
                'confidence_score': confidence_score,
                'classification_outputs': classification_outputs,
                'prediction_error': '',
                'behavior_analyzed_at': timezone.now(),
            },
        )
        if script_text.strip():
            analyze_and_update_video_chunk(analysis_row.id)
            analysis_row.refresh_from_db()
        # Keep video file for 12 hours (see cleanup_old_videos); analysis rows stay forever.
        logger.info(
            'Screen chunk analysis complete — video retained for 12h | clip_id=%s user=%s',
            clip_id,
            clip.user_id,
        )
    except Exception as exc:
        logger.exception('Video analysis failed for clip %s', clip_id)
        failed_clip = VideoClip.objects.filter(id=clip_id).first()
        if failed_clip is not None:
            VideoChunkAnalysis.objects.update_or_create(
                source_clip=failed_clip,
                defaults={
                    'user': failed_clip.user,
                    'chunk_id': _clip_chunk_id(failed_clip),
                    'session_id': _clip_session_id(failed_clip),
                    'script_text': (failed_clip.script_text or '')[:8000],
                    'platform': failed_clip.platform,
                    'duration_seconds': failed_clip.duration_seconds,
                    'source_package': failed_clip.source_package,
                    'content_type': dict(DEFAULT_CONTENT_TYPE),
                    'client_created_at_ms': _client_created_at_ms(failed_clip),
                    'behavior_result': '',
                    'confidence_score': 0.0,
                    'classification_outputs': {},
                    'prediction_error': str(exc)[:4000],
                    'behavior_analyzed_at': timezone.now(),
                },
            )
        VideoClip.objects.filter(id=clip_id).update(
            analysis_status=VideoClip.STATUS_FAILED,
            analysis_error=str(exc)[:4000],
            processed_at=timezone.now(),
        )
    finally:
        close_old_connections()


def ensure_pending_chunk_analysis(clip: VideoClip) -> VideoChunkAnalysis:
    """Create or refresh analysis row as soon as a clip is uploaded (before async vision runs)."""
    meta = clip.content_type if isinstance(clip.content_type, dict) else {}
    content_payload = dict(meta)
    content_payload.setdefault('detected_app_name', clip.platform or meta.get('app_name') or '')
    content_payload.setdefault('timestamp_start', meta.get('start_time') or '')
    content_payload.setdefault('timestamp_end', meta.get('end_time') or '')
    if clip.file and getattr(clip.file, 'name', ''):
        content_payload.setdefault('video_chunk_file', clip.file.name)
    row, _ = VideoChunkAnalysis.objects.update_or_create(
        source_clip=clip,
        defaults={
            'user': clip.user,
            'chunk_id': _clip_chunk_id(clip),
            'session_id': _clip_session_id(clip),
            'platform': clip.platform,
            'duration_seconds': clip.duration_seconds,
            'source_package': clip.source_package,
            'client_created_at_ms': _client_created_at_ms(clip),
            'script_text': (clip.script_text or '').strip(),
            'content_type': content_payload,
        },
    )
    return row


def submit_video_clip_analysis(clip_id: int) -> None:
    _ANALYSIS_EXECUTOR.submit(_analyze_video_clip_sync, clip_id)


def process_video_clip_now(clip_id: int) -> None:
    _analyze_video_clip_sync(clip_id)


def backfill_incomplete_clip_results(clip_id: int) -> dict[str, bool]:
    """
    Repair pipeline outputs for an existing clip if any piece is missing.
    Stages:
      1) script generation (vision model) if script missing
      2) content_type classification (text model) if missing
      3) behavior prediction (ensemble_final_model) if missing
    """
    close_old_connections()
    filled = {
        'script_filled': False,
        'content_type_filled': False,
        'behavior_filled': False,
    }
    try:
        clip = VideoClip.objects.filter(id=clip_id).first()
        if clip is None:
            return filled

        analysis_row, _ = VideoChunkAnalysis.objects.get_or_create(
            source_clip=clip,
            defaults={
                'user': clip.user,
                'chunk_id': _clip_chunk_id(clip),
                'session_id': _clip_session_id(clip),
                'script_text': clip.script_text or '',
                'platform': clip.platform,
                'duration_seconds': clip.duration_seconds,
                'source_package': clip.source_package,
                'content_type': clip.content_type or {},
                'client_created_at_ms': _client_created_at_ms(clip),
            },
        )

        needs_reprocess = _requires_reprocessing(clip, analysis_row)
        has_file = bool(getattr(clip, 'file', None)) and bool(getattr(clip.file, 'name', ''))
        file_exists = has_file and os.path.exists(clip.file.path)

        if needs_reprocess and file_exists:
            aggregated = _run_consolidated_pipeline(clip.file.path)
            script_text = str(aggregated.get('final_script') or '')
            content_type = aggregated.get('content_analysis_result') or {}
            behavior_result = str(aggregated.get('final_behavior_result') or '')
            confidence_score = float(aggregated.get('final_confidence_score') or 0.0)
            classification_outputs = aggregated.get('classification_outputs') or {}
            classification_outputs['frame_summary'] = aggregated.get('frame_summary') or []
            clip.script_text = script_text
            clip.content_type = content_type
            analysis_row.script_text = script_text
            analysis_row.content_type = content_type
            analysis_row.behavior_result = behavior_result
            analysis_row.behavior_results = {
                'behavior_result': behavior_result,
                'confidence_score': confidence_score,
                'classification_outputs': classification_outputs,
            }
            analysis_row.confidence_score = confidence_score
            analysis_row.classification_outputs = classification_outputs
            analysis_row.prediction_error = ''
            analysis_row.behavior_analyzed_at = timezone.now()
            filled['script_filled'] = True
            filled['content_type_filled'] = True
            filled['behavior_filled'] = True
        else:
            script_text = (clip.script_text or analysis_row.script_text or '').strip()
            if not script_text:
                raise RuntimeError('Script is missing and source video file is unavailable for regeneration.')
            content_type = clip.content_type or analysis_row.content_type or {}
            if (not isinstance(content_type, dict)) or (not content_type):
                content_type = _classify_script(script_text)
                clip.content_type = content_type
                analysis_row.content_type = content_type
                filled['content_type_filled'] = True
            if not _text_present(analysis_row.script_text):
                analysis_row.script_text = script_text
                filled['script_filled'] = True

        clip.analysis_status = VideoClip.STATUS_COMPLETED
        clip.processed_at = timezone.now()
        clip.analysis_error = ''
        clip.save(
            update_fields=[
                'script_text',
                'content_type',
                'analysis_status',
                'processed_at',
                'analysis_error',
            ]
        )
        analysis_row.platform = clip.platform
        analysis_row.duration_seconds = clip.duration_seconds
        analysis_row.source_package = clip.source_package
        analysis_row.client_created_at_ms = _client_created_at_ms(clip)
        analysis_row.save(
            update_fields=[
                'script_text',
                'content_type',
                'platform',
                'duration_seconds',
                'source_package',
                'client_created_at_ms',
            ]
        )

        behavior_missing = not (analysis_row.behavior_result or '').strip()
        behavior_missing = behavior_missing or not (analysis_row.behavior_results or {})
        behavior_missing = behavior_missing or analysis_row.confidence_score is None
        if behavior_missing and script_text.strip():
            analyze_and_update_video_chunk(analysis_row.id)
            analysis_row.refresh_from_db()
            filled['behavior_filled'] = bool((analysis_row.behavior_result or '').strip())

        return filled
    except Exception as exc:
        logger.exception('Backfill failed for clip %s', clip_id)
        VideoClip.objects.filter(id=clip_id).update(
            analysis_error=str(exc)[:4000],
            processed_at=timezone.now(),
        )
        return filled
    finally:
        close_old_connections()
