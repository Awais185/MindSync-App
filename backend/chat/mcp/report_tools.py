"""Data aggregation for MCP chat tools (7-day report & 24h symptom diagnostic)."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, time, timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from chat.behavior_context import merge_behavior_context
from chat.models import UserMentalState
from face_detection.models import FacialExpressionCapture
from tracking.models import ScreenTime
from users.models import ScreenUsageEvent
from users.services.behavioral_insights_analytics import build_facial_expression_study, build_seven_day_chunk_analytics
from users.services.weekly_report_builder import _current_week_bounds, build_seven_day_report_payload

REPORT_HEADER = '## Your 7-day MindSync wellness report'

_HIGH_SCREEN_SECONDS_PER_DAY = 6 * 3600
_LATE_NIGHT_START = 22  # 10 PM
_LATE_NIGHT_END = 6  # 6 AM


def _hm(total_seconds: int) -> str:
    total_seconds = max(0, int(total_seconds))
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    if h:
        return f'{h}h {m}m'
    return f'{m}m'


def _is_late_night(dt: datetime) -> bool:
    h = timezone.localtime(dt).hour
    return h >= _LATE_NIGHT_START or h < _LATE_NIGHT_END


_SYMPTOM_KEYWORDS: dict[str, tuple[str, ...]] = {
    'headache': ('headache', 'migraine', 'head pain', 'head hurts'),
    'eye_strain': ('eye strain', 'eye pain', 'eyes hurt', 'dry eyes', 'blurry vision', 'screen hurts my eyes'),
    'fatigue': ('fatigue', 'tired', 'exhausted', 'burned out', 'low energy'),
    'neck_pain': ('neck pain', 'neck hurts', 'stiff neck', 'shoulder pain'),
}


def extract_reported_symptoms(message: str) -> list[str]:
    lower = (message or '').lower()
    found: list[str] = []
    for label, phrases in _SYMPTOM_KEYWORDS.items():
        if any(p in lower for p in phrases):
            found.append(label)
    return found


def _symptom_display(label: str) -> str:
    return {
        'headache': 'headache',
        'eye_strain': 'eye strain / eye pain',
        'fatigue': 'fatigue',
        'neck_pain': 'neck or shoulder discomfort',
    }.get(label, label.replace('_', ' '))


def build_seven_day_comprehensive_report(
    user: User,
    client_behavior: dict[str, Any] | None = None,
) -> str:
    """Formatted 7-day wellness report for chat display."""
    start_day, end_day, days = _current_week_bounds()
    payload = build_seven_day_report_payload(user, end_day=end_day)
    merged = merge_behavior_context(user, client_behavior)

    screen_rows = ScreenTime.objects.filter(user=user, date__range=(start_day, end_day))
    daily_seconds = [int(r.total_screen_time) for r in screen_rows]
    week_total_sec = sum(daily_seconds)
    days_with_data = len(daily_seconds) or 1
    avg_sec = int(week_total_sec / max(len(days), 1))

    events = list(ScreenUsageEvent.objects.filter(user=user, date__range=(start_day, end_day)))
    late_sec = sum(e.usage_time for e in events if _is_late_night(e.end_time))
    late_apps: dict[str, int] = defaultdict(int)
    for e in events:
        if _is_late_night(e.end_time):
            name = (e.app_name or e.package_name or 'Other').strip()
            late_apps[name] += int(e.usage_time)
    top_late = sorted(late_apps.items(), key=lambda x: -x[1])[:5]

    top_apps_week: dict[str, int] = defaultdict(int)
    for e in events:
        name = (e.app_name or e.package_name or 'Other').strip()
        top_apps_week[name] += int(e.usage_time)
    top_apps = sorted(top_apps_week.items(), key=lambda x: -x[1])[:6]

    try:
        state = user.mental_state
    except UserMentalState.DoesNotExist:
        state = None
    latest_expression = (
        FacialExpressionCapture.objects.filter(
            user=user,
            status=FacialExpressionCapture.STATUS_COMPLETED,
        )
        .order_by('-created_at')
        .first()
    )

    start_at = timezone.make_aware(datetime.combine(start_day, time.min))
    end_at = timezone.make_aware(datetime.combine(end_day, time.max))
    facial_study = build_facial_expression_study(user, start_at, end_at)
    chunk_analytics = build_seven_day_chunk_analytics(
        user, start_day=start_day, end_day=end_day, days=days
    )
    mh_block = chunk_analytics.get('mental_health') or {}
    behaviour_raw = mh_block.get('behaviour_insight')
    if isinstance(behaviour_raw, dict):
        behaviour_insight = (behaviour_raw.get('message') or behaviour_raw.get('text') or '').strip()
    else:
        behaviour_insight = (behaviour_raw or '').strip() if behaviour_raw else ''
    mh_summary = (mh_block.get('summary_message') or '').strip()
    if isinstance(mh_summary, dict):
        mh_summary = (mh_summary.get('message') or '').strip()

    lines: list[str] = [
        REPORT_HEADER,
        '',
        '_Personalized from your screen-time, facial scans, and content signals over the last 7 days._',
        '',
    ]

    lines.append('## Screen time (last 7 days)')
    lines.append(f'- **Total:** {_hm(week_total_sec)}')
    lines.append(f'- **Daily average:** {_hm(avg_sec)}')
    if top_apps:
        lines.append('- Most used apps: ' + ', '.join(f'{n} ({_hm(s)})' for n, s in top_apps))

    sleep_track = {}
    analytics = payload.get('analytics') if isinstance(payload.get('analytics'), dict) else {}
    if isinstance(analytics.get('sleep_tracking'), dict):
        sleep_track = analytics['sleep_tracking']
    tracked_nights = int(sleep_track.get('tracked_nights') or 0)
    lines.append('')
    lines.append('## Sleep & late-night activity')
    if tracked_nights > 0:
        lines.append(f'- **Nights with tracked sleep:** {tracked_nights} (from screen-time sleep window)')
    lines.append(f'- **Late-night phone use (10 PM – 6 AM):** {_hm(late_sec)}')
    if sleep_track.get('total_late_night_hours'):
        lines.append(
            f'- **Late-night total (report rollup):** {float(sleep_track["total_late_night_hours"]):.1f} h'
        )
    if top_late:
        lines.append(
            '- Top late-night apps: ' + ', '.join(f'{n} ({_hm(s)})' for n, s in top_late)
        )
    else:
        lines.append('- No significant late-night sessions recorded in this period.')

    lines.append('')
    lines.append('## Facial study & mood signals')
    mood = merged.get('mood_indicators') or {}
    snap = payload.get('wellbeing_snapshot') if isinstance(payload.get('wellbeing_snapshot'), dict) else {}
    week_emotion = str(snap.get('latest_emotion') or '').strip()
    if latest_expression:
        emo = (latest_expression.emotion or '').strip() or week_emotion
        lines.append(
            f'- Latest expression capture — Emotion: {emo or "n/a"}, '
            f'Stress: {latest_expression.stress_score}, '
            f'Depression: {latest_expression.depression_score}'
        )
    elif mood.get('face_stress') is not None:
        lines.append(
            f'- Stress / depression (recent): {mood.get("face_stress")} / '
            f'{mood.get("face_depression")}'
        )
    elif week_emotion:
        lines.append(f'- Dominant emotion this week: {week_emotion}')
    if state:
        lines.append(
            f'- Profile indicators — emotion: {state.emotion or "n/a"}, '
            f'stress level: {state.stress_level or "n/a"}, sleep quality: {state.sleep_quality or "n/a"}'
        )
    if facial_study.get('has_data'):
        for row in (facial_study.get('classes') or [])[:4]:
            if isinstance(row, dict) and row.get('label'):
                lines.append(f'- Expression study: {row.get("label")} ({row.get("count", 0)} samples)')

    lines.append('')
    lines.append('### Synthesis')
    synthesis_bits: list[str] = []
    if avg_sec >= _HIGH_SCREEN_SECONDS_PER_DAY:
        synthesis_bits.append(
            f'Your **{_hm(avg_sec)}** daily average screen time is above the 6h comfort zone — '
            'pair shorter evening sessions with a fixed wind-down.'
        )
    elif avg_sec > 0:
        synthesis_bits.append(
            f'Screen time averages **{_hm(avg_sec)}** per day — a workable baseline if late-night use stays low.'
        )
    if late_sec >= 3600:
        synthesis_bits.append(
            f'**{_hm(late_sec)}** after 10 PM suggests sleep debt risk; try moving high-stimulation apps earlier in the day.'
        )
    if latest_expression:
        emo = (latest_expression.emotion or '').strip() or week_emotion
        emo_bit = f', emotion **{emo}**' if emo else ''
        synthesis_bits.append(
            f'Latest expression capture: stress **{latest_expression.stress_score}**, '
            f'depression **{latest_expression.depression_score}**{emo_bit} — '
            'use these as a weekly trend, not a diagnosis.'
        )
    elif mh_summary:
        synthesis_bits.append(mh_summary.strip(' .'))
    if not synthesis_bits:
        synthesis_bits.append(
            'Keep logging scans and screen time so MindSync can surface sharper week-over-week patterns.'
        )
    for bit in synthesis_bits[:3]:
        lines.append(f'- {bit}')

    lines.append('')
    lines.append('## Insights & improvement focus')
    rec = payload.get('recommendations') or {}
    if isinstance(rec, dict):
        sections = rec.get('sections') or []
        if isinstance(sections, list) and sections:
            lines.append('')
            lines.append('## Personalized recommendations')
            for sec in sections[:4]:
                if not isinstance(sec, dict):
                    continue
                title = (sec.get('title') or 'Tips').strip()
                lines.append(f'### {title}')
                for bullet in (sec.get('bullets') or [])[:4]:
                    lines.append(f'- {bullet}')
        for_user = rec.get('for_user') or []
        if isinstance(for_user, list):
            if not sections:
                lines.append('')
                lines.append('## Personalized recommendations')
            for s in for_user[:6]:
                lines.append(f'- {s}')
    summary = (merged.get('seven_day_summary') or '').strip()
    if summary:
        lines.append(f'- {summary}')
    if mh_summary:
        lines.append(f'- {mh_summary}')
    if behaviour_insight:
        lines.append(f'- {behaviour_insight}')
    insights = payload.get('ai_insights') or payload.get('insights') or []
    if isinstance(insights, list):
        for item in insights[:3]:
            lines.append(f'- {item}')

    lines.append('')
    lines.append('## Alerts & watch-outs')
    alerts: list[str] = []
    if avg_sec >= _HIGH_SCREEN_SECONDS_PER_DAY:
        alerts.append(
            f'Your average daily screen time ({_hm(avg_sec)}) is high — consider scheduled breaks and a digital sunset.'
        )
    if late_sec >= 3600:
        alerts.append(
            'Frequent late-night phone use can disrupt sleep and increase next-day fatigue or eye strain.'
        )
    analytics = payload.get('analytics') or {}
    weekly_cmp = analytics.get('weekly_comparison') if isinstance(analytics, dict) else {}
    if isinstance(weekly_cmp, dict):
        imp = weekly_cmp.get('improvement_percentage')
        if imp is not None and float(imp) < 0:
            alerts.append(
                'Screen time trended upward versus the prior week — a gentle reduction goal may help.'
            )
    if not alerts:
        alerts.append('No critical patterns flagged; keep balancing rest, movement, and screen breaks.')
    for a in alerts:
        lines.append(f'- {a}')

    lines.append('')
    lines.append(
        '_Tip: Use the Report tab for charts. I can help you turn these insights into a simple daily plan._'
    )
    return '\n'.join(lines)


def build_symptom_diagnostic_report(
    user: User,
    message: str,
    client_behavior: dict[str, Any] | None = None,
) -> str:
    """Correlate reported symptoms with last 24h device usage."""
    symptoms = extract_reported_symptoms(message)
    if not symptoms:
        symptoms = ['fatigue']

    since = timezone.now() - timedelta(hours=24)
    events = list(
        ScreenUsageEvent.objects.filter(user=user, end_time__gte=since).order_by('-end_time')
    )
    total_sec = sum(e.usage_time for e in events)
    late_sec = sum(e.usage_time for e in events if _is_late_night(e.end_time))

    app_totals: dict[str, int] = defaultdict(int)
    for e in events:
        name = (e.app_name or e.package_name or 'Other').strip()
        app_totals[name] += int(e.usage_time)
    top_apps = sorted(app_totals.items(), key=lambda x: -x[1])[:5]

    symptom_text = ', '.join(_symptom_display(s) for s in symptoms)
    lines: list[str] = [
        f"## Symptom check-in: {symptom_text}",
        '',
        "Here's what your **last 24 hours** of device activity shows:",
        '',
        f'- **Total screen time (24h):** {_hm(total_sec)}',
        f'- **Late-night usage (10 PM – 6 AM):** {_hm(late_sec)}',
    ]
    if top_apps:
        lines.append('- Most used apps: ' + ', '.join(f'{n} ({_hm(s)})' for n, s in top_apps))
    else:
        lines.append('- No detailed app sessions were synced for the last 24 hours yet.')

    lines.append('')
    lines.append('## Likely connection')
    high_use = total_sec >= 3 * 3600
    if high_use or late_sec >= 45 * 60:
        lines.append(
            'Higher screen time and/or late-night sessions often contribute to eye strain, headaches, '
            'and mental fatigue — especially with social or video apps.'
        )
        if top_apps:
            lead = top_apps[0][0]
            lines.append(
                f'You spent notable time on {lead} — consider shorter sessions and the 20-20-20 rule '
                '(every 20 minutes, look 20 feet away for 20 seconds).'
            )
    else:
        lines.append(
            'Your recorded screen time is moderate for the last day. Symptoms may also relate to sleep, '
            'hydration, or stress — still worth resting your eyes and taking movement breaks.'
        )

    lines.append('')
    lines.append('## Gentle next steps')
    lines.append('- 10–15 minute break away from screens, dim brightness, and hydrate.')
    lines.append('- If headache or eye pain persists, consider speaking with a healthcare professional.')
    lines.append('- Would you like a breathing exercise or a lighter evening screen plan for tonight?')

    return '\n'.join(lines)
