"""Aggregate face, behavior, and screen signals into UserMentalState per user."""

from __future__ import annotations

from django.contrib.auth.models import User
from django.utils import timezone

from chat.models import UserMentalState


def _score_to_stress_label(stress: int, anxiety: int, depression: int) -> str:
    from users.mental_health_severity import severity_label_from_percent

    peak = max(stress, anxiety, depression)
    if peak <= 0:
        return 'not recorded'
    return severity_label_from_percent(peak)


def _format_screen_time(total_seconds: int) -> str:
    if total_seconds <= 0:
        return 'not recorded'
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    if hours:
        return f'{hours}h {minutes}m today'
    return f'{minutes}m today'


def _sleep_quality_from_events(events) -> str:
    late_seconds = sum(
        e.usage_time for e in events if e.end_time.hour >= 23 or e.end_time.hour < 5
    )
    if late_seconds >= 5400:
        return 'poor (heavy late-night usage)'
    if late_seconds >= 1800:
        return 'fair (some late-night usage)'
    if late_seconds > 0:
        return 'moderate'
    return 'not recorded'


def _behavior_summary(*parts: str) -> str:
    cleaned = [p.strip() for p in parts if p and p.strip()]
    return ' · '.join(cleaned[:6]) if cleaned else ''


def sync_user_mental_state(user: User) -> UserMentalState:
    """Rebuild mental-state fields from the latest per-user sensor rows."""
    from face_detection.models import FacialExpressionCapture, MentalHealthResult
    from tracking.models import ScreenTime
    from users.models import ScreenUsageEvent, VideoChunkAnalysis

    state, _ = UserMentalState.objects.get_or_create(user=user)
    today = timezone.localdate()

    latest_face = (
        MentalHealthResult.objects.filter(user=user).order_by('-timestamp').first()
    )
    latest_expression = (
        FacialExpressionCapture.objects.filter(
            user=user,
            status=FacialExpressionCapture.STATUS_COMPLETED,
        )
        .order_by('-created_at')
        .first()
    )
    latest_chunk = VideoChunkAnalysis.objects.filter(user=user).order_by('-created_at').first()

    screen_row = ScreenTime.objects.filter(user=user, date=today).first()
    events_today = list(ScreenUsageEvent.objects.filter(user=user, date=today))
    event_total = sum(e.usage_time for e in events_today)
    total_seconds = int(screen_row.total_screen_time) if screen_row else 0
    if event_total > total_seconds:
        total_seconds = event_total

    stress = anxiety = depression = 0
    if latest_face:
        stress, anxiety, depression = (
            latest_face.stress_score,
            latest_face.anxiety_score,
            latest_face.depression_score,
        )
    elif latest_expression:
        stress = latest_expression.stress_score
        anxiety = 0
        depression = latest_expression.depression_score

    state.stress_level = _score_to_stress_label(stress, anxiety, depression)

    emotion = 'not recorded'
    if latest_face and latest_face.dominant_state:
        emotion = latest_face.dominant_state.replace('_', ' ')
    elif latest_expression and latest_expression.dominant_state:
        emotion = latest_expression.dominant_state.replace('_', ' ')
    elif latest_chunk:
        ct = latest_chunk.content_type if isinstance(latest_chunk.content_type, dict) else {}
        main = ct.get('main_emotion') or ct.get('dominant_mood')
        if isinstance(main, str) and main.strip():
            emotion = main.strip()
        elif latest_chunk.behavior_result:
            emotion = latest_chunk.behavior_result.replace('_', ' ')

    state.emotion = emotion
    state.screen_time = _format_screen_time(total_seconds)
    state.sleep_quality = _sleep_quality_from_events(events_today)

    behavior_parts: list[str] = []
    if latest_face and isinstance(latest_face.behavioral_insights, list):
        for item in latest_face.behavioral_insights[:3]:
            if isinstance(item, str):
                behavior_parts.append(item)
            elif isinstance(item, dict):
                text = item.get('text') or item.get('insight')
                if isinstance(text, str):
                    behavior_parts.append(text)
    if latest_chunk:
        if latest_chunk.behavior_result:
            behavior_parts.append(f'Recent activity signal: {latest_chunk.behavior_result}')
        ct = latest_chunk.content_type if isinstance(latest_chunk.content_type, dict) else {}
        summary = ct.get('summary')
        if isinstance(summary, str) and summary.strip():
            behavior_parts.append(summary.strip()[:240])
    if latest_expression and latest_expression.active_aus:
        aus = latest_expression.active_aus[:4]
        if aus:
            behavior_parts.append(f'Facial AU activity: {", ".join(str(a) for a in aus)}')

    state.behavior = _behavior_summary(*behavior_parts)
    state.save()
    return state


def refresh_user_tracking_snapshots(user: User) -> None:
    """Update mental state immediately; debounce persisted 7-day report writes."""
    sync_user_mental_state(user)
    from users.services.snapshot_scheduler import schedule_weekly_report_rebuild

    schedule_weekly_report_rebuild(user.id)
