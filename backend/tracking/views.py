"""Video upload, screen-time upsert, and face verification (cosine on image vectors)."""

from __future__ import annotations

import logging
import os
from collections import defaultdict
from datetime import date, datetime, timedelta

from django.utils import timezone
from django.db.models import Avg, Count, Q
from django.db import connection
from django.db.utils import OperationalError, ProgrammingError
from rest_framework import parsers, permissions, response, status, views

from chat.models import ChatMessage
from face_detection.profile_face_verify import verify_probe_for_user
from users.models import ScreenUsageEvent, UserProfile, VideoChunkAnalysis

from .models import FaceVerificationEvent, ScreenTime, VideoClip
from .serializers import FaceVerificationEventSerializer, ScreenTimeUpdateSerializer
from .services import ensure_pending_chunk_analysis, submit_video_clip_analysis
from subscriptions.permissions import require_subscription_feature
from subscriptions.services import SubscriptionService

logger = logging.getLogger(__name__)


class VideoUploadView(views.APIView):
    """
    POST /api/video/upload/
    multipart: video_clip, platform, timestamp (optional ISO), user_id (ignored — uses JWT user).
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if 'video_clip' not in request.data:
            return response.Response(
                {'error': 'video_clip file is required'}, status=status.HTTP_400_BAD_REQUEST
            )
        platform = (request.data.get('platform') or 'Unknown').strip() or 'Unknown'
        source_package = (request.data.get('source_package') or '').strip()
        raw_ts = request.data.get('timestamp')
        duration_seconds = int(request.data.get('duration_seconds') or 0)
        try:
            chunk_index = int(request.data.get('chunk_index', 0))
        except (TypeError, ValueError):
            chunk_index = 0
        chunk_index = max(0, chunk_index)
        client_timestamp = None
        if raw_ts:
            from django.utils.dateparse import parse_datetime

            client_timestamp = parse_datetime(str(raw_ts))
            if client_timestamp and timezone.is_naive(client_timestamp):
                client_timestamp = timezone.make_aware(
                    client_timestamp, timezone.get_current_timezone()
                )

        capture_meta = {
            'recording_type': (request.data.get('recording_type') or 'screen').strip() or 'screen',
            'session_id': (request.data.get('session_id') or '').strip(),
            'device_id': (request.data.get('device_id') or '').strip(),
            'app_name': (request.data.get('app_name') or platform).strip()[:120],
            'package_name': (request.data.get('package_name') or source_package).strip()[:200],
            'start_time': (request.data.get('start_time') or '').strip(),
            'end_time': (request.data.get('end_time') or '').strip(),
        }
        app_label = capture_meta.get('app_name') or platform
        chunk_duration = max(0, duration_seconds) or 30
        ts_label = timezone.now().strftime('%Y-%m-%d %H:%M:%S')
        analysis_table = VideoChunkAnalysis._meta.db_table
        if not _table_exists(analysis_table):
            err = f'database table missing: {analysis_table}'
            logger.error('Failed to save video chunk: %s', err)
            print(f'❌ Failed to save video chunk — Reason: {err}', flush=True)
            return response.Response(
                {'error': 'video_chunk_analysis_table_missing'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        try:
            clip = VideoClip.objects.create(
                user=request.user,
                file=request.data['video_clip'],
                platform=platform[:64],
                source_package=source_package[:200] or None,
                duration_seconds=chunk_duration,
                chunk_index=chunk_index,
                client_timestamp=client_timestamp,
                analysis_status=VideoClip.STATUS_PENDING,
                content_type={k: v for k, v in capture_meta.items() if v},
            )
            analysis_row = ensure_pending_chunk_analysis(clip)
        except Exception as exc:
            logger.exception('Failed to save video chunk for user=%s', request.user.id)
            print(f'❌ Failed to save video chunk — Reason: {exc}', flush=True)
            return response.Response(
                {'error': 'video_chunk_save_failed', 'detail': str(exc)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        msg = (
            f'✅ Video chunk saved — App: {app_label} | Duration: {chunk_duration}s | '
            f'Time: {ts_label} | user={request.user.id} clip_id={clip.id} '
            f'analysis_id={analysis_row.id} session={capture_meta.get("session_id") or "n/a"}'
        )
        logger.info(msg)
        print(msg, flush=True)
        submit_video_clip_analysis(clip.id)
        return response.Response(
            {
                'ok': True,
                'id': clip.id,
                'analysis_id': analysis_row.id,
                'chunk_id': f'clip-{clip.id}',
                'chunk_index': clip.chunk_index,
                'platform': clip.platform,
                'source_package': clip.source_package,
                'duration_seconds': clip.duration_seconds,
                'analysis_status': clip.analysis_status,
                'status_url': f'/api/video/upload/{clip.id}/',
                'created_at': clip.created_at.isoformat(),
            },
            status=status.HTTP_201_CREATED,
        )


class VideoUploadStatusView(views.APIView):
    """GET /api/video/upload/<clip_id>/ - polling endpoint for analysis results."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request, clip_id: int):
        clip = VideoClip.objects.filter(id=clip_id, user=request.user).first()
        if clip is None:
            return response.Response({'error': 'clip_not_found'}, status=status.HTTP_404_NOT_FOUND)

        plan_code = SubscriptionService.current_plan_code(request.user)
        is_premium = plan_code == 'premium'
        payload = {
            'id': clip.id,
            'chunk_id': f'clip-{clip.id}',
            'platform': clip.platform,
            'source_package': clip.source_package,
            'duration_seconds': clip.duration_seconds,
            'analysis_status': clip.analysis_status,
            'analysis_error': clip.analysis_error,
            'script_text': clip.script_text,
            'content_type': clip.content_type,
            'created_at': clip.created_at.isoformat(),
            'processed_at': clip.processed_at.isoformat() if clip.processed_at else None,
        }
        return response.Response(payload, status=status.HTTP_200_OK)


class ScreenTimeUpdateView(views.APIView):
    """POST /api/screen-time/update/ — delta or absolute daily totals."""

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        ser = ScreenTimeUpdateSerializer(data=request.data)
        if not ser.is_valid():
            return response.Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        data = ser.validated_data
        day: date = data.get('date') or timezone.now().date()

        row, _ = ScreenTime.objects.get_or_create(
            user=request.user,
            date=day,
            defaults={
                'total_screen_time': 0,
                'social_media_time': 0,
                'video_watch_time': 0,
            },
        )

        if data.get('mode', 'delta') == 'absolute':
            row.total_screen_time = int(data['total_screen_time'])
            row.social_media_time = int(data.get('social_media_time') or 0)
            row.video_watch_time = int(data.get('video_watch_time') or 0)
            row.save()
        else:
            from django.db.models import F
            delta_total = int(data.get('delta_total') or 0)
            delta_social = int(data.get('delta_social') or 0)
            delta_video = int(data.get('delta_video') or 0)
            
            ScreenTime.objects.filter(id=row.id).update(
                total_screen_time=F('total_screen_time') + delta_total,
                social_media_time=F('social_media_time') + delta_social,
                video_watch_time=F('video_watch_time') + delta_video,
            )
            row.refresh_from_db()
        try:
            from users.services.mental_state_sync import refresh_user_tracking_snapshots

            refresh_user_tracking_snapshots(request.user)
        except Exception:
            pass
        return response.Response(
            {
                'date': row.date.isoformat(),
                'total_screen_time': row.total_screen_time,
                'social_media_time': row.social_media_time,
                'video_watch_time': row.video_watch_time,
            }
        )


class ScreenTimeTodayView(views.APIView):
    """GET /api/screen-time/today/ — current user's row for today (create empty if missing)."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        day = timezone.now().date()
        row, _ = ScreenTime.objects.get_or_create(
            user=request.user,
            date=day,
            defaults={
                'total_screen_time': 0,
                'social_media_time': 0,
                'video_watch_time': 0,
            },
        )
        return response.Response(
            {
                'date': row.date.isoformat(),
                'total_screen_time': row.total_screen_time,
                'social_media_time': row.social_media_time,
                'video_watch_time': row.video_watch_time,
                'updated_at': row.updated_at.isoformat(),
            }
        )


class FaceVerifyView(views.APIView):
    """
    POST /api/face-verify/
    multipart: image (live face). Compares to the authenticated user's enrolled face
    (same embedding pipeline as /api/face/verify-track/).
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if 'image' not in request.data:
            return response.Response({'error': 'image is required'}, status=status.HTTP_400_BAD_REQUEST)

        uploaded = request.data['image'].read()
        unlock_capture = str(
            request.data.get('source') or request.data.get('capture_context') or ''
        ).strip().lower() in {'unlock', 'background', 'unlock_verify'}

        raw_thr = request.data.get('match_threshold') or os.environ.get(
            'FACE_VERIFY_TRACK_THRESHOLD',
            os.environ.get('FACE_MATCH_THRESHOLD', os.environ.get('FACE_COSINE_THRESHOLD', '0.80')),
        )
        try:
            threshold = float(raw_thr)
        except (TypeError, ValueError):
            threshold = 0.80

        profile, result = verify_probe_for_user(
            request.user,
            uploaded,
            threshold=threshold,
            unlock_capture=unlock_capture,
        )
        if profile is None:
            return response.Response(
                {'error': result.get('error', 'Profile not found'), 'allowed': False},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not profile.face_image:
            return response.Response(
                {'error': 'Face not enrolled', 'allowed': False},
                status=status.HTTP_400_BAD_REQUEST,
            )

        matched = bool(result.get('matched'))
        probability = float(result.get('probability') or 0.0)
        return response.Response(
            {
                'allowed': matched,
                'matched': matched,
                'match': matched,
                'similarity': probability,
                'similarity_percent': round(probability * 100.0, 2),
                'probability': result.get('probability'),
                'distance': result.get('distance'),
                'threshold': result.get('threshold'),
                'status': result.get('status'),
                'method': result.get('method'),
                'reject_reason': result.get('reject_reason'),
                'warning': None
                if matched
                else 'Face does not match enrolled profile. Tracking and recording are disabled.',
                **{k: v for k, v in result.items() if k.startswith('laplacian') or k == 'face_area_percent'},
            },
            status=status.HTTP_200_OK,
        )


class FaceVerificationEventView(views.APIView):
    """
    POST /api/face-verification/events/
    Store unlock/screen-on/app-resume verification metadata for analytics/auditing.
    """

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        ser = FaceVerificationEventSerializer(data=request.data)
        if not ser.is_valid():
            return response.Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        data = ser.validated_data
        match_percent = float(data['verified_face_match_percent'])
        event = FaceVerificationEvent.objects.create(
            user=request.user,
            event_type=data['event_type'],
            unlock_timestamp=data.get('unlock_timestamp'),
            screen_on_timestamp=data.get('screen_on_timestamp'),
            session_duration_seconds=int(data.get('session_duration_seconds') or 0),
            verified_face_match_percent=match_percent,
            is_verified=match_percent >= 80.0,
            app_usage_stats=data.get('app_usage_stats') or {},
        )
        return response.Response(
            {
                'id': event.id,
                'event_type': event.event_type,
                'is_verified': event.is_verified,
                'verified_face_match_percent': event.verified_face_match_percent,
                'created_at': event.created_at.isoformat(),
            },
            status=status.HTTP_201_CREATED,
        )


class FaceVerificationAnalyticsView(views.APIView):
    """GET /api/face-verification/analytics/?range=day|week|month"""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        selected = (request.query_params.get('range') or 'week').strip().lower()
        if selected not in {'day', 'week', 'month'}:
            selected = 'week'

        window_days = _range_days(selected)
        days, start_at, end_at = _last_n_days_window(window_days)

        qs = FaceVerificationEvent.objects.filter(
            user=request.user,
            created_at__gte=start_at,
            created_at__lte=end_at,
        )

        total_events = qs.count()
        verified_events = qs.filter(is_verified=True).count()
        avg_match = qs.aggregate(v=Avg('verified_face_match_percent'))['v'] or 0.0
        event_breakdown = {
            row['event_type']: row['total']
            for row in qs.values('event_type').annotate(total=Count('id'))
        }
        daily_map = {
            row['created_at__date']: {
                'total': int(row['total']),
                'verified': int(row['verified']),
            }
            for row in qs.values('created_at__date').annotate(
                total=Count('id'),
                verified=Count('id', filter=Q(is_verified=True)),
            )
        }
        daily_verification = []
        for day in days:
            row = daily_map.get(day, {'total': 0, 'verified': 0})
            total = int(row['total'])
            verified = int(row['verified'])
            daily_verification.append(
                {
                    'date': day.isoformat(),
                    'total_events': total,
                    'verified_events': verified,
                    'verification_rate_percent': round((verified / total) * 100.0, 2) if total else 0.0,
                }
            )

        return response.Response(
            {
                'range': selected,
                'total_events': total_events,
                'verified_events': verified_events,
                'failed_events': max(0, total_events - verified_events),
                'verification_rate_percent': round(
                    (verified_events / total_events) * 100.0, 2
                )
                if total_events
                else 0.0,
                'avg_face_match_percent': round(float(avg_match), 2),
                'event_breakdown': event_breakdown,
                'window_days': window_days,
                'daily_verification': daily_verification,
            }
        )


def _extract_content_categories(content_type: dict) -> list[str]:
    categories: list[str] = []
    if not isinstance(content_type, dict):
        return categories

    direct = content_type.get('content_type') or content_type.get('category')
    if isinstance(direct, str) and direct.strip():
        categories.append(direct.strip().lower())

    labels = content_type.get('labels')
    if isinstance(labels, list):
        for item in labels:
            if isinstance(item, str) and item.strip():
                categories.append(item.strip().lower())

    if not categories:
        categories.append('other')
    return categories


def _extract_mood_label(content_type: dict) -> str:
    if not isinstance(content_type, dict):
        return 'neutral'
    mood = content_type.get('main_emotion') or content_type.get('emotion')
    if isinstance(mood, str) and mood.strip():
        return mood.strip().lower()
    return 'neutral'


def _range_days(selected: str) -> int:
    if selected == 'day':
        return 1
    if selected == 'month':
        return 30
    return 7


def _last_n_days_window(n_days: int) -> tuple[list[date], timezone.datetime, timezone.datetime]:
    end_day = timezone.localdate()
    start_day = end_day - timedelta(days=max(0, n_days - 1))
    days = [start_day + timedelta(days=i) for i in range(n_days)]
    start_at = timezone.make_aware(datetime.combine(start_day, datetime.min.time()), timezone.get_current_timezone())
    end_at = timezone.now()
    return days, start_at, end_at


class BehavioralAnalyticsView(views.APIView):
    """GET /api/analytics/behavioral/?range=day|week|month"""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        selected = (request.query_params.get('range') or 'week').strip().lower()
        if selected not in {'day', 'week', 'month'}:
            selected = 'week'

        window_days = _range_days(selected)
        days, start_at, end_at = _last_n_days_window(window_days)

        chunks = VideoChunkAnalysis.objects.filter(
            user=request.user,
            created_at__gte=start_at,
            created_at__lte=end_at,
        ).order_by('created_at')

        content_counts: dict[str, int] = {}
        mood_counts: dict[str, int] = {}
        mood_by_day: dict[date, dict[str, int]] = defaultdict(dict)
        category_by_day: dict[date, dict[str, int]] = defaultdict(dict)

        from users.services.category_session_analytics import session_category_for_chunk

        for chunk in chunks:
            chunk_day = timezone.localtime(chunk.created_at).date()
            cat = session_category_for_chunk(chunk.content_type or {}, chunk.source_package)
            content_counts[cat] = content_counts.get(cat, 0) + 1
            by_day_counts = category_by_day[chunk_day]
            by_day_counts[cat] = by_day_counts.get(cat, 0) + 1
            mood = _extract_mood_label(chunk.content_type or {})
            mood_counts[mood] = mood_counts.get(mood, 0) + 1
            day_moods = mood_by_day[chunk_day]
            day_moods[mood] = day_moods.get(mood, 0) + 1

        total_content_samples = sum(content_counts.values())
        top_categories = sorted(
            content_counts.items(),
            key=lambda item: item[1],
            reverse=True,
        )[:5]
        top_categories_payload = [
            {
                'category': name,
                'count': count,
                'percent': round((count / total_content_samples) * 100.0, 2)
                if total_content_samples
                else 0.0,
            }
            for name, count in top_categories
        ]

        total_mood_samples = sum(mood_counts.values())
        mood_frequency = [
            {
                'mood': mood,
                'count': count,
                'percent': round((count / total_mood_samples) * 100.0, 2)
                if total_mood_samples
                else 0.0,
            }
            for mood, count in sorted(mood_counts.items(), key=lambda item: item[1], reverse=True)
        ]
        dominant_mood = mood_frequency[0]['mood'] if mood_frequency else 'neutral'
        dominant_mood_daily = []
        top_content_daily = []
        for day in days:
            mood_map = mood_by_day.get(day, {})
            category_map = category_by_day.get(day, {})
            top_mood = 'neutral'
            if mood_map:
                top_mood = max(mood_map.items(), key=lambda item: item[1])[0]
            top_category = 'other'
            top_count = 0
            if category_map:
                top_category, top_count = max(category_map.items(), key=lambda item: item[1])

            dominant_mood_daily.append(
                {
                    'date': day.isoformat(),
                    'mood': top_mood,
                    'count': int(mood_map.get(top_mood, 0)) if mood_map else 0,
                    'total_samples': int(sum(mood_map.values())) if mood_map else 0,
                }
            )
            top_content_daily.append(
                {
                    'date': day.isoformat(),
                    'category': top_category,
                    'count': int(top_count),
                    'total_samples': int(sum(category_map.values())) if category_map else 0,
                }
            )

        from users.services.category_session_analytics import build_category_session
        from users.services.behavioral_insights_analytics import (
            build_behaviour_insight,
            build_content_preference_top3,
            build_unified_behavioral_insights,
        )
        from users.wellbeing import content_theme_buckets_for_analytics

        category_session = build_category_session(request.user, start_at, end_at)
        session_categories = category_session.get('categories') or []
        # Prefer chunk-based session categories when we have analysed data.
        if session_categories:
            top_categories_payload = session_categories
        theme_buckets = content_theme_buckets_for_analytics(request.user, start_at, end_at)
        unified = build_unified_behavioral_insights(
            request.user,
            start_at,
            end_at,
            window_days=window_days,
        )
        content_preference = build_content_preference_top3(
            request.user,
            start_at,
            end_at,
        )
        behaviour_insight = build_behaviour_insight(
            request.user,
            start_at,
            end_at,
            window_days=window_days,
        )

        return response.Response(
            {
                'range': selected,
                'top_content_categories': top_categories_payload,
                'category_session': category_session,
                'content_preference': content_preference,
                'behaviour_insight': behaviour_insight,
                'theme_content_categories': theme_buckets,
                'mood_frequency': mood_frequency,
                'dominant_mood': dominant_mood,
                'total_analyzed_chunks': chunks.count(),
                'window_days': window_days,
                'dominant_mood_daily': dominant_mood_daily,
                'top_content_daily': top_content_daily,
                **unified,
            }
        )


def _seconds_to_hm(total_seconds: int) -> str:
    total_seconds = max(0, int(total_seconds))
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    return f'{h}h {m:02d}m'


def _clamp(val: float, low: float, high: float) -> float:
    return max(low, min(high, val))


def _table_exists(table_name: str) -> bool:
    try:
        return table_name in connection.introspection.table_names()
    except Exception:
        return False


class WeeklyReportView(views.APIView):
    """GET /api/reports/weekly/ - 7-day behavioral report for authenticated user."""

    permission_classes = (permissions.IsAuthenticated,)

    @require_subscription_feature(
        'weekly_reports',
        'Upgrade to Premium to access weekly analysis reports',
    )
    def get(self, request):
        from users.services.weekly_report_builder import build_and_save_weekly_report, build_seven_day_report_payload

        build_and_save_weekly_report(request.user)
        payload = build_seven_day_report_payload(request.user)
        return response.Response(payload, status=status.HTTP_200_OK)
