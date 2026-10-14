"""Build structured behaviour context for Digital Psychologist chat (Gemini system prompt)."""

from __future__ import annotations

import json
from collections import defaultdict
from datetime import timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from chat.models import UserMentalState

_CONTEXT_PREFIX = (
    'You are a supportive mental health assistant for the MindSync app. '
    "Here is the user's recent behaviour data:\n"
)
_CONTEXT_SUFFIX = (
    '\nUse this data to personalise your responses and provide relevant mental health insights. '
    'Do not repeat the raw data back to the user — use it silently to inform your answers.'
)

_EMPTY_CONTEXT = 'No usage data available yet.'

_ACTIVITY_CHART_KEYWORDS = (
    'screen time',
    'screentime',
    'usage',
    'app usage',
    'activity',
    'stats',
    'statistics',
    'weekly',
    'monthly',
    'daily',
    'how much',
    'how long',
    'show me my',
    'my data',
    'breakdown',
    'chart',
    'graph',
    'late night',
    'content type',
    'what did i watch',
    'summary',
    'report',
    'trend',
    'compare',
)


def user_wants_activity_charts(message: str) -> bool:
    """Charts only when the user asks about usage, stats, or activity."""
    msg = (message or '').strip().lower()
    if len(msg) < 4:
        return False
    return any(keyword in msg for keyword in _ACTIVITY_CHART_KEYWORDS)


def _hm(total_seconds: int) -> str:
    total_seconds = max(0, int(total_seconds))
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    if h:
        return f'{h}h {m}m'
    return f'{m}m'


def _section(title: str, lines: list[str]) -> str:
    body = [ln for ln in lines if ln and ln.strip()]
    if not body:
        return ''
    return f'[{title}]\n' + '\n'.join(f'- {ln}' for ln in body)


def _merge_client_section(client: dict[str, Any] | None, key: str) -> dict[str, Any]:
    if not isinstance(client, dict):
        return {}
    block = client.get(key)
    return block if isinstance(block, dict) else {}


def _format_content_items(items: list[Any], *, limit: int = 5) -> list[str]:
    out: list[str] = []
    for raw in items[:limit]:
        if not isinstance(raw, dict):
            continue
        label = (raw.get('label') or raw.get('category') or raw.get('name') or '').strip()
        if not label:
            continue
        pct = raw.get('percent')
        count = raw.get('count')
        if pct is not None:
            out.append(f'{label} ({pct}%)')
        elif count is not None:
            out.append(f'{label} ({count} chunks)')
        else:
            out.append(label)
    return out


def build_server_behavior_context(user: User) -> dict[str, Any]:
    """Aggregate Django DB signals for the authenticated user."""
    from face_detection.models import FacialExpressionCapture, MentalHealthResult
    from tracking.models import ScreenTime
    from users.models import ScreenUsageEvent, UserWeeklyReport, VideoChunkAnalysis
    from users.services.behavioral_insights_analytics import build_seven_day_chunk_analytics
    from users.services.weekly_report_builder import _current_week_bounds

    today = timezone.localdate()
    start_day, end_day, days = _current_week_bounds(today)

    screen_row = ScreenTime.objects.filter(user=user, date=today).first()
    events_today = list(ScreenUsageEvent.objects.filter(user=user, date=today))
    event_total = sum(e.usage_time for e in events_today)
    day_total = int(screen_row.total_screen_time) if screen_row else 0
    if event_total > day_total:
        day_total = event_total

    social_today = int(screen_row.social_media_time) if screen_row else 0
    video_today = int(screen_row.video_watch_time) if screen_row else 0
    gaming_today = max(0, day_total - social_today - video_today) if day_total else 0

    late_night_today = sum(
        e.usage_time for e in events_today if e.end_time.hour >= 23 or e.end_time.hour < 5
    )
    late_categories: dict[str, int] = defaultdict(int)
    for e in events_today:
        if e.end_time.hour >= 23 or e.end_time.hour < 5:
            name = (e.app_name or e.package_name or 'Other').strip()
            late_categories[name] += int(e.usage_time)

    week_rows = ScreenTime.objects.filter(user=user, date__range=(start_day, end_day))
    week_total = sum(int(r.total_screen_time) for r in week_rows)
    week_social = sum(int(r.social_media_time) for r in week_rows)
    week_video = sum(int(r.video_watch_time) for r in week_rows)

    week_events = ScreenUsageEvent.objects.filter(user=user, date__range=(start_day, end_day))
    late_night_week = sum(
        e.usage_time for e in week_events if e.end_time.hour >= 23 or e.end_time.hour < 5
    )

    chunk_analytics = build_seven_day_chunk_analytics(
        user, start_day=start_day, end_day=end_day, days=days
    )
    content_items = (chunk_analytics.get('content_type') or {}).get('items') or []
    mh_summary = (chunk_analytics.get('mental_health') or {}).get('summary_message') or ''
    behaviour_insight = (chunk_analytics.get('mental_health') or {}).get('behaviour_insight') or ''

    from datetime import datetime, time

    from users.services.behavioral_insights_analytics import build_facial_expression_study

    start_at = timezone.make_aware(datetime.combine(start_day, time.min))
    end_at = timezone.make_aware(datetime.combine(end_day, time.max))
    facial_study = build_facial_expression_study(user, start_at, end_at)
    facial_lines: list[str] = []
    if facial_study.get('has_data'):
        for row in facial_study.get('classes') or []:
            if not isinstance(row, dict):
                continue
            label = (row.get('label') or '').strip()
            count = row.get('count')
            valid = row.get('valid_detections')
            if label and ((count or 0) > 0 or (valid or 0) > 0):
                facial_lines.append(f'{label}: {count or valid} detections')

    try:
        state = user.mental_state
    except UserMentalState.DoesNotExist:
        state = None

    latest_face = MentalHealthResult.objects.filter(user=user).order_by('-timestamp').first()
    latest_expression = (
        FacialExpressionCapture.objects.filter(
            user=user,
            status=FacialExpressionCapture.STATUS_COMPLETED,
        )
        .order_by('-created_at')
        .first()
    )

    sleep_hours_est = None
    weekly_report = UserWeeklyReport.objects.filter(user=user, week_start=start_day).first()
    seven_day_summary = ''
    if weekly_report and isinstance(weekly_report.payload, dict):
        payload = weekly_report.payload
        insights = payload.get('ai_insights') or payload.get('insights') or []
        if isinstance(insights, list) and insights:
            seven_day_summary = '; '.join(str(x) for x in insights[:4])
        day_data = payload.get('seven_day_data') or payload.get('day_reports') or []
        if isinstance(day_data, list) and day_data:
            last = day_data[-1] if day_data else {}
            if isinstance(last, dict):
                sleep_hours_est = last.get('sleep_time_hours')

    if sleep_hours_est is None and week_rows.exists():
        avg_late = late_night_week / 7.0
        sleep_hours_est = round(max(4.5, 8.0 - (avg_late / 3600.0) * 0.35), 1)

    chunk_count = VideoChunkAnalysis.objects.filter(
        user=user, created_at__date__range=(start_day, end_day)
    ).count()

    return {
        'screen_time': {
            'today_total': _hm(day_total),
            'today_social': _hm(social_today),
            'today_gaming': _hm(gaming_today),
            'today_entertainment_video': _hm(video_today),
            'week_total': _hm(week_total),
            'week_social': _hm(week_social),
            'week_video': _hm(week_video),
        },
        'late_night': {
            'today_duration': _hm(late_night_today),
            'week_duration': _hm(late_night_week),
            'top_apps_today': [
                f'{k} ({_hm(v)})' for k, v in sorted(late_categories.items(), key=lambda x: -x[1])[:5]
            ],
        },
        'content_types': _format_content_items(content_items),
        'facial_expression_summary': facial_lines,
        'behaviour_insights': [
            x
            for x in [
                mh_summary if isinstance(mh_summary, str) else '',
                behaviour_insight if isinstance(behaviour_insight, str) else '',
                state.behavior if state and state.behavior else '',
            ]
            if x
            and x.strip()
            and 'no mental health data' not in x.lower()
            and 'not recorded' not in x.lower()
        ],
        'mood_indicators': {
            'stress': state.stress_level if state else 'not recorded',
            'emotion': state.emotion if state else 'not recorded',
            'sleep_quality': state.sleep_quality if state else 'not recorded',
            'face_stress': latest_face.stress_score if latest_face else None,
            'face_anxiety': latest_face.anxiety_score if latest_face else None,
            'face_depression': latest_face.depression_score if latest_face else None,
            'expression_dominant': (
                latest_expression.dominant_state if latest_expression else None
            ),
        },
        'sleep_estimate': {
            'hours': sleep_hours_est,
            'quality_note': state.sleep_quality if state else 'not recorded',
        },
        'seven_day_summary': seven_day_summary,
        'observed_chunks_7d': chunk_count,
    }


def _client_has_signal(client: dict[str, Any] | None) -> bool:
    if not isinstance(client, dict) or not client:
        return False
    if client.get('has_data') is False:
        return False
    for value in client.values():
        if value in (None, '', [], {}, 0):
            continue
        return True
    return False


def merge_behavior_context(
    user: User,
    client_payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Prefer fresh device snapshot where provided; fill gaps from server DB."""
    server = build_server_behavior_context(user)
    if not _client_has_signal(client_payload):
        return server

    merged = dict(server)
    client = client_payload or {}

    screen_client = _merge_client_section(client, 'screen_time')
    if screen_client:
        merged['screen_time'] = {**merged.get('screen_time', {}), **screen_client}

    late_client = _merge_client_section(client, 'late_night')
    if late_client:
        base = dict(merged.get('late_night', {}))
        base.update(late_client)
        merged['late_night'] = base

    if client.get('content_types'):
        merged['content_types'] = client['content_types']
    if client.get('behaviour_insights'):
        existing = merged.get('behaviour_insights') or []
        extra = client['behaviour_insights']
        if isinstance(extra, list):
            merged['behaviour_insights'] = list(dict.fromkeys([*existing, *extra]))[:8]

    mood_client = _merge_client_section(client, 'mood_indicators')
    if mood_client:
        merged['mood_indicators'] = {**merged.get('mood_indicators', {}), **mood_client}

    sleep_client = _merge_client_section(client, 'sleep_estimate')
    if sleep_client:
        merged['sleep_estimate'] = {**merged.get('sleep_estimate', {}), **sleep_client}

    if client.get('seven_day_summary'):
        merged['seven_day_summary'] = client['seven_day_summary']

    if client.get('observed_chunks_7d') is not None:
        merged['observed_chunks_7d'] = client['observed_chunks_7d']

    merged['source'] = 'device+server'
    return merged


def format_behavior_context_text(context: dict[str, Any] | None) -> str:
    if not context or not _context_has_data(context):
        return _EMPTY_CONTEXT

    sections: list[str] = []

    st = context.get('screen_time') or {}
    screen_lines = [
        f"Today total: {st.get('today_total')}" if st.get('today_total') else '',
        f"Today social: {st.get('today_social')}" if st.get('today_social') else '',
        f"Today gaming (est.): {st.get('today_gaming')}" if st.get('today_gaming') else '',
        f"Today video/entertainment: {st.get('today_entertainment_video')}"
        if st.get('today_entertainment_video')
        else '',
        f"Last 7 days total: {st.get('week_total')}" if st.get('week_total') else '',
        f"Last 7 days social: {st.get('week_social')}" if st.get('week_social') else '',
    ]
    top_apps = st.get('top_apps_today') or []
    if isinstance(top_apps, list) and top_apps:
        screen_lines.append(f"Top apps today: {', '.join(str(a) for a in top_apps[:6])}")
    block = _section('Daily screen time', screen_lines)
    if block:
        sections.append(block)

    ln = context.get('late_night') or {}
    late_lines = [
        f"Late-night today (10pm–5am): {ln.get('today_duration')}" if ln.get('today_duration') else '',
        f"Late-night last 7 days: {ln.get('week_duration')}" if ln.get('week_duration') else '',
    ]
    cats = ln.get('top_apps_today') or ln.get('categories_tonight') or ln.get('categories_week') or []
    if isinstance(cats, list) and cats:
        late_lines.append(f"Late-night app categories/apps: {', '.join(str(c) for c in cats[:6])}")
    block = _section('Late-night activity', late_lines)
    if block:
        sections.append(block)

    content = context.get('content_types') or []
    if isinstance(content, list) and content:
        sections.append(_section('Content types most watched', [str(c) for c in content[:5]]))

    facial_summary = context.get('facial_expression_summary') or []
    if isinstance(facial_summary, list) and facial_summary:
        sections.append(
            _section('Facial expression study (7 days)', [str(x) for x in facial_summary[:6]])
        )

    insights = context.get('behaviour_insights') or []
    if isinstance(insights, list) and insights:
        sections.append(_section('Behavioural insights', [str(x) for x in insights[:6]]))

    mood = context.get('mood_indicators') or {}
    if isinstance(mood, dict) and mood:
        mood_lines = []
        for key, label in (
            ('stress', 'Stress level'),
            ('emotion', 'Dominant emotion'),
            ('sleep_quality', 'Sleep quality signal'),
            ('wellbeing_score', 'Wellbeing score'),
            ('stress_score', 'Stress score'),
            ('anxiety_score', 'Anxiety score'),
            ('depression_score', 'Depression score'),
            ('face_stress', 'Facial stress score'),
            ('face_anxiety', 'Facial anxiety score'),
            ('face_depression', 'Facial depression score'),
            ('expression_dominant', 'Latest facial expression'),
        ):
            val = mood.get(key)
            if val is not None and str(val).strip() and str(val) != 'not recorded':
                mood_lines.append(f'{label}: {val}')
        block = _section('Mood & mental health indicators', mood_lines)
        if block:
            sections.append(block)

    sleep = context.get('sleep_estimate') or {}
    if isinstance(sleep, dict):
        sleep_lines = []
        if sleep.get('hours') is not None:
            sleep_lines.append(f"Estimated sleep: ~{sleep.get('hours')} hours")
        if sleep.get('tonight_minutes') is not None:
            sleep_lines.append(f"Sleep tonight (device): {_hm(int(sleep['tonight_minutes']) * 60)}")
        if sleep.get('week_minutes') is not None:
            sleep_lines.append(f"Sleep last 7 days (device): {_hm(int(sleep['week_minutes']) * 60)}")
        if sleep.get('quality_note'):
            sleep_lines.append(f"Quality note: {sleep['quality_note']}")
        block = _section('Sleep estimate', sleep_lines)
        if block:
            sections.append(block)

    summary = (context.get('seven_day_summary') or '').strip()
    if summary:
        sections.append(_section('Last 7 days summary', [summary]))

    chunks = context.get('observed_chunks_7d')
    if chunks:
        sections.append(_section('Activity sampling', [f'{chunks} analysed video/screen chunks in last 7 days']))

    if not sections:
        return _EMPTY_CONTEXT
    return '\n\n'.join(sections)


def _context_has_data(context: dict[str, Any]) -> bool:
    if context.get('seven_day_summary'):
        return True
    chunks = context.get('observed_chunks_7d')
    if chunks and int(chunks) > 0:
        return True
    st = context.get('screen_time') or {}
    for key in ('today_total', 'week_total', 'today_social', 'week_social'):
        val = st.get(key)
        if val and val not in ('0m', '0h 0m'):
            return True
    if context.get('content_types') or context.get('behaviour_insights'):
        return True
    if context.get('facial_expression_summary'):
        return True
    mood = context.get('mood_indicators') or {}
    for val in mood.values():
        if val is not None and str(val).strip() not in ('', 'not recorded', '0'):
            return True
    ln = context.get('late_night') or {}
    for key in ('today_duration', 'week_duration'):
        val = ln.get(key)
        if val and val not in ('0m', '0h 0m'):
            return True
    sleep = context.get('sleep_estimate') or {}
    if sleep.get('hours') and float(sleep['hours']) > 0:
        return True
    if sleep.get('tonight_minutes') and int(sleep['tonight_minutes']) > 0:
        return True
    if sleep.get('week_minutes') and int(sleep['week_minutes']) > 0:
        return True
    return False


def build_gemini_behavior_system_prompt(
    user: User,
    client_payload: dict[str, Any] | None = None,
    *,
    base_prompt: str,
) -> str:
    merged = merge_behavior_context(user, client_payload)
    body = format_behavior_context_text(merged)
    return f'{base_prompt.strip()}\n\n{_CONTEXT_PREFIX}{body}{_CONTEXT_SUFFIX}'.strip()


def build_chat_charts(
    user: User,
    client_payload: dict[str, Any] | None = None,
    *,
    user_message: str = '',
) -> list[dict[str, Any]]:
    """Structured chart payloads — only when user asks about activity/stats."""
    if not user_wants_activity_charts(user_message):
        return []
    ctx = merge_behavior_context(user, client_payload)
    charts: list[dict[str, Any]] = []

    try:
        from tracking.models import ScreenTime
        from users.services.weekly_report_builder import _current_week_bounds

        start_day, end_day, day_list = _current_week_bounds()
        by_date = {
            r.date: r
            for r in ScreenTime.objects.filter(user=user, date__range=(start_day, end_day))
        }
        labels: list[str] = []
        hours: list[float] = []
        for d in day_list:
            labels.append(d.strftime('%a'))
            row = by_date.get(d)
            sec = int(row.total_screen_time) if row else 0
            hours.append(round(sec / 3600.0, 2))
        if any(v > 0 for v in hours):
            charts.append(
                {
                    'type': 'bar',
                    'title': 'Screen Time (7 Days)',
                    'labels': labels,
                    'values': hours,
                    'series_label': 'Hours',
                }
            )
    except Exception:
        pass

    mood = ctx.get('mood_indicators') or {}
    mood_labels: list[str] = []
    mood_values: list[float] = []
    for label, key in (
        ('Stress', 'stress_score'),
        ('Anxiety', 'anxiety_score'),
        ('Depression', 'depression_score'),
        ('Stress', 'face_stress'),
        ('Anxiety', 'face_anxiety'),
        ('Depression', 'face_depression'),
    ):
        if label in mood_labels:
            continue
        val = mood.get(key)
        if val is None or str(val).strip() in ('', 'not recorded'):
            continue
        try:
            mood_labels.append(label)
            mood_values.append(float(val))
        except (TypeError, ValueError):
            continue
    if mood_values:
        charts.append(
            {
                'type': 'bar',
                'title': 'Mental Health Scores',
                'labels': mood_labels,
                'values': mood_values,
                'series_label': 'Score',
            }
        )

    content_labels: list[str] = []
    content_values: list[float] = []
    for raw in ctx.get('content_types') or []:
        if isinstance(raw, dict):
            name = (raw.get('label') or raw.get('category') or raw.get('name') or '').strip()
            pct = raw.get('percent') or raw.get('value')
        else:
            text = str(raw).strip()
            if '(' not in text:
                continue
            name = text.split('(')[0].strip()
            pct = text.split('(')[1].replace(')', '').replace('%', '').strip()
        if not name:
            continue
        try:
            content_labels.append(name)
            content_values.append(float(pct))
        except (TypeError, ValueError):
            continue
    if content_values:
        charts.append(
            {
                'type': 'donut',
                'title': 'Content Types',
                'labels': content_labels,
                'values': content_values,
            }
        )

    return charts


def parse_client_behavior_payload(raw: Any) -> dict[str, Any] | None:
    if raw is None:
        return None
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return None
        try:
            parsed = json.loads(text)
            return parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            return None
    return None
