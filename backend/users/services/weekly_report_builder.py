"""Build and persist the 7-day report payload shown in the mobile Report screen."""

from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta

from django.contrib.auth.models import User
from django.db import connection
from django.db.utils import OperationalError, ProgrammingError
from django.utils import timezone

from chat.models import ChatMessage
from tracking.models import ScreenTime
from users.models import ScreenUsageEvent, UserWeeklyReport, VideoChunkAnalysis
from users.mental_health_severity import severity_label_from_percent


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


def _current_week_bounds(end_day: date | None = None) -> tuple[date, date, list[date]]:
    end_day = end_day or timezone.localdate()
    start_day = end_day - timedelta(days=6)
    days = [start_day + timedelta(days=i) for i in range(7)]
    return start_day, end_day, days


def build_seven_day_report_payload(
    user: User,
    *,
    end_day: date | None = None,
    include_premium_insights: bool | None = None,
) -> dict:
    """Return structured 7-day analytics JSON scoped to the given user."""
    from django.db.models import Count

    from subscriptions.services import SubscriptionService

    start_day, end_day, days = _current_week_bounds(end_day)
    if include_premium_insights is None:
        include_premium_insights = SubscriptionService.current_plan_code(user) == 'premium'

    from users.mental_health_scoring import compute_mental_health_scores
    from users.openface_home_metrics import latest_predicted_emotion
    from users.wellbeing import build_wellness_dashboard

    wellness_block = build_wellness_dashboard(user, days=7)
    mh_scores = compute_mental_health_scores(user, window_days=7)
    wellbeing_snapshot = {
        'wellbeing_score': int(wellness_block.get('wellbeing_score') or 0),
        'mental_health_score': int(wellness_block.get('mental_health_score') or 0),
        'stress': float((mh_scores.get('stress') or {}).get('score') or 0),
        'depression': float((mh_scores.get('depression') or {}).get('score') or 0),
        'latest_emotion': latest_predicted_emotion(user),
        'has_mental_health_data': bool(mh_scores.get('has_data')),
        'has_wellbeing_signal': bool(wellness_block.get('has_wellbeing_signal')),
    }

    screen_rows = ScreenTime.objects.filter(user=user, date__range=(start_day, end_day))
    screen_map = {row.date: row for row in screen_rows}

    usage_events = ScreenUsageEvent.objects.none()
    if _table_exists(ScreenUsageEvent._meta.db_table):
        usage_events = ScreenUsageEvent.objects.filter(user=user, date__range=(start_day, end_day))
    event_by_day: dict[date, list] = defaultdict(list)
    app_distribution = {'Instagram': 0, 'TikTok': 0, 'YouTube': 0, 'Others': 0}

    for event in usage_events:
        event_by_day[event.date].append(event)
        app_name = (event.app_name or '').lower()
        package = (event.package_name or '').lower()
        merged = f'{app_name} {package}'
        if 'instagram' in merged:
            app_distribution['Instagram'] += event.usage_time
        elif 'tiktok' in merged or 'musically' in merged:
            app_distribution['TikTok'] += event.usage_time
        elif 'youtube' in merged:
            app_distribution['YouTube'] += event.usage_time
        else:
            app_distribution['Others'] += event.usage_time

    message_counts_qs = (
        ChatMessage.objects.filter(user=user, created_at__date__range=(start_day, end_day))
        .values('created_at__date')
        .annotate(total=Count('id'))
    )
    message_counts = {row['created_at__date']: row['total'] for row in message_counts_qs}

    chunk_rows = VideoChunkAnalysis.objects.none()
    if _table_exists(VideoChunkAnalysis._meta.db_table):
        chunk_rows = VideoChunkAnalysis.objects.filter(
            user=user, created_at__date__range=(start_day, end_day)
        )
    chunks_by_day: dict[date, int] = defaultdict(int)
    try:
        for row in chunk_rows:
            chunks_by_day[row.created_at.date()] += 1
    except (OperationalError, ProgrammingError):
        chunks_by_day = defaultdict(int)

    day_reports = []
    stress_trend: list[int] = []
    mood_stability_trend: list[int] = []
    screen_time_trend: list[float] = []
    social_trend: list[float] = []
    late_night_trend: list[float] = []
    productivity_scores: list[int] = []
    sleep_scores: list[int] = []

    for current_day in days:
        screen = screen_map.get(current_day)
        total_seconds = int(screen.total_screen_time) if screen else 0
        social_seconds = int(screen.social_media_time) if screen else 0
        video_seconds = int(screen.video_watch_time) if screen else 0

        events = event_by_day.get(current_day, [])
        if events:
            event_total = sum(e.usage_time for e in events)
            if event_total > total_seconds:
                total_seconds = event_total

        late_night_seconds = sum(
            e.usage_time for e in events if e.end_time.hour >= 23 or e.end_time.hour < 5
        )
        night_intensity = _clamp(late_night_seconds / 5400.0, 0, 1)

        screen_hours = total_seconds / 3600.0
        social_ratio = (social_seconds / total_seconds) if total_seconds else 0
        stress_score = int(
            _clamp(25 + (screen_hours * 8) + (social_ratio * 25) + (night_intensity * 30), 18, 95)
        )
        stability_score = int(_clamp(100 - (stress_score * 0.72), 20, 92))
        productivity_score = int(_clamp(82 - (screen_hours * 5.5) - (night_intensity * 18), 22, 90))
        sleep_seconds_tracked = int(screen.sleep_time) if screen and screen.sleep_time else 0
        if sleep_seconds_tracked > 0:
            sleep_hours = sleep_seconds_tracked / 3600.0
            sleep_score = int(_clamp((sleep_hours / 8.0) * 100, 40, 100))
            sleep_data_source = 'screen_time_table'
        else:
            sleep_hours = _clamp(
                8.1 - max(0, screen_hours - 4) * 0.3 - (night_intensity * 1.4),
                4.5,
                8.6,
            )
            sleep_score = int(_clamp((sleep_hours / 8.0) * 100, 40, 100))
            sleep_data_source = 'estimated'

        stress_level = severity_label_from_percent(stress_score)
        if stress_score >= 76:
            dominant_mood = 'Irritable'
            anxiety_indicator = severity_label_from_percent(min(100, stress_score + 8))
        elif stress_score >= 60:
            dominant_mood = 'Uneasy'
            anxiety_indicator = severity_label_from_percent(stress_score)
        elif stress_score >= 45:
            dominant_mood = 'Neutral'
            anxiety_indicator = severity_label_from_percent(stress_score)
        else:
            dominant_mood = 'Calm'
            anxiety_indicator = severity_label_from_percent(stress_score)

        if productivity_score >= 70:
            productivity_level = 'High'
        elif productivity_score >= 50:
            productivity_level = 'Moderate'
        else:
            productivity_level = 'Low'

        sleep_start = ''
        if sleep_seconds_tracked > 0:
            sleep_start = 'Tracked (10 PM–6 AM window)'

        note = (
            f"{message_counts.get(current_day, 0)} chat interactions, "
            f"{chunks_by_day.get(current_day, 0)} observed activity chunks. "
            f"{'Late-night usage spike detected.' if late_night_seconds > 2700 else 'Daily pattern within expected range.'}"
        )

        day_reports.append(
            {
                'day': f'Day {len(day_reports) + 1}',
                'date': current_day.isoformat(),
                'total_screen_time': total_seconds,
                'social_media_time': social_seconds,
                'video_watch_time': video_seconds,
                'sleep_time_hours': round(float(sleep_hours), 2),
                'sleep_start': sleep_start,
                'sleep_data_source': sleep_data_source,
                'dominant_mood': dominant_mood,
                'stress_level': stress_level,
                'stress_score': stress_score,
                'anxiety_indicator': anxiety_indicator,
                'productivity_level': productivity_level,
                'productivity_score': productivity_score,
                'late_night_usage_seconds': int(late_night_seconds),
                'notes': note,
            }
        )

        stress_trend.append(stress_score)
        mood_stability_trend.append(stability_score)
        screen_time_trend.append(round(total_seconds / 3600.0, 2))
        social_trend.append(round(social_seconds / 3600.0, 2))
        late_night_trend.append(round(late_night_seconds / 3600.0, 2))
        productivity_scores.append(productivity_score)
        sleep_scores.append(sleep_score)

    avg_screen_seconds = int(sum(d['total_screen_time'] for d in day_reports) / 7)
    avg_stress = int(sum(stress_trend) / 7)
    avg_sleep_score = int(sum(sleep_scores) / 7)
    avg_productivity = int(sum(productivity_scores) / 7)
    emotional_stability = int(sum(mood_stability_trend) / 7)
    late_night_days = sum(1 for h in late_night_trend if h >= 0.5)

    risk_score = int(
        _clamp((avg_stress * 0.48) + ((100 - avg_sleep_score) * 0.22) + (late_night_days * 6), 10, 98)
    )
    if risk_score < 35:
        risk_level = {'level': 'Normal', 'color': 'green', 'score': risk_score}
    elif risk_score < 55:
        risk_level = {'level': 'Mild Concern', 'color': 'yellow', 'score': risk_score}
    elif risk_score < 75:
        risk_level = {'level': 'Moderate Concern', 'color': 'orange', 'score': risk_score}
    else:
        risk_level = {'level': 'High Concern', 'color': 'red', 'score': risk_score}

    previous_start = start_day - timedelta(days=7)
    previous_end = start_day - timedelta(days=1)
    prev_screen = ScreenTime.objects.filter(user=user, date__range=(previous_start, previous_end)).count()
    previous_avg_screen = 0
    if prev_screen:
        previous_total = sum(
            r.total_screen_time
            for r in ScreenTime.objects.filter(user=user, date__range=(previous_start, previous_end))
        )
        previous_avg_screen = int(previous_total / 7)
    improvement_pct = 0
    if previous_avg_screen > 0:
        improvement_pct = round(((previous_avg_screen - avg_screen_seconds) / previous_avg_screen) * 100, 1)

    try:
        usage_count = usage_events.count()
    except (OperationalError, ProgrammingError):
        usage_count = 0
    try:
        chunk_count = chunk_rows.count()
    except (OperationalError, ProgrammingError):
        chunk_count = 0
    confidence_inputs = screen_rows.count() + usage_count + chunk_count + sum(message_counts.values())
    confidence_score = int(_clamp(45 + (confidence_inputs * 2.4), 52, 97))

    insights = []
    if late_night_days >= 3:
        insights.append('Stress increased on days with higher night usage, especially after 11 PM.')
    if sum(1 for d in day_reports if d['video_watch_time'] > 3600) >= 2:
        insights.append('Mood stability dropped after prolonged short-video consumption windows.')
    if sum(1 for d in day_reports if d['total_screen_time'] < avg_screen_seconds) >= 3:
        insights.append('Lower screen-time days correlate with better emotional balance and productivity.')
    if avg_sleep_score < 68:
        insights.append('Sleep irregularity may be contributing to anxiety-linked behavioral patterns.')

    try:
        from users.services.mood_weekly_service import build_weekly_mood_payload

        mood_weekly = build_weekly_mood_payload(user, request=None)
    except Exception:
        mood_weekly = {}

    from users.mental_health_daily import build_seven_day_condition_breakdown

    from users.services.behavioral_insights_analytics import build_seven_day_chunk_analytics

    chunk_analytics = build_seven_day_chunk_analytics(
        user,
        start_day=start_day,
        end_day=end_day,
        days=days,
    )

    condition_breakdown = build_seven_day_condition_breakdown(
        user,
        start_day=start_day,
        end_day=end_day,
        days=days,
        chunk_analytics=chunk_analytics,
    )
    chunk_screen_daily = {
        row['date']: int(row.get('seconds') or 0)
        for row in (chunk_analytics.get('screen_time') or {}).get('daily') or []
    }
    for dr, bd in zip(day_reports, condition_breakdown.get('days', [])):
        for key in ('stress', 'depression'):
            val = bd.get(key)
            if val is not None:
                dr[f'{key}_score'] = int(round(float(val)))
        emo = bd.get('emotion')
        if emo:
            dr['emotion'] = str(emo)
            dr['dominant_mood'] = str(emo)
        day_iso = dr.get('date')
        chunk_sec = chunk_screen_daily.get(day_iso, 0)
        screen_sec = bd.get('screen_time_seconds')
        if chunk_sec > 0:
            dr['total_screen_time'] = int(chunk_sec)
            dr['screen_time_source'] = 'video_chunks'
        elif screen_sec is not None and int(screen_sec) > 0:
            dr['total_screen_time'] = int(screen_sec)
            dr['screen_time_source'] = 'screen_time_table'
    chunk_hours = [
        round((chunk_screen_daily.get(d.isoformat(), 0) / 3600.0), 2) for d in days
    ]
    if any(h > 0 for h in chunk_hours):
        screen_time_trend = chunk_hours
        avg_screen_seconds = int(sum(d['total_screen_time'] for d in day_reports) / 7)

    depression_trend: list[int | None] = []
    for row in (condition_breakdown.get('days') or []):
        if isinstance(row, dict):
            dep = row.get('depression')
            depression_trend.append(int(round(float(dep))) if dep is not None else None)
        else:
            depression_trend.append(None)

    content_items = (chunk_analytics.get('content_type') or {}).get('items') or []
    if content_items and not insights:
        top = content_items[0]
        insights.append(
            f"Most watched content type: {top.get('label', 'Unknown')} "
            f"({top.get('percent', 0)}% of analysed chunks)."
        )
    mh_summary = (chunk_analytics.get('mental_health') or {}).get('summary_message')
    if mh_summary and mh_summary not in insights:
        insights.append(str(mh_summary))

    tracked_sleep_nights = sum(
        1 for d in day_reports if d.get('sleep_data_source') == 'screen_time_table'
    )
    total_late_night_sec = sum(int(d.get('late_night_usage_seconds') or 0) for d in day_reports)

    draft_payload = {
        'wellbeing_snapshot': wellbeing_snapshot,
        'user': {
            'full_name': f'{user.first_name} {user.last_name}'.strip() or user.username,
            'report_period': f'{start_day.isoformat()} to {end_day.isoformat()}',
        },
        'seven_day_data': day_reports,
        'analytics': {'progress_cards': {'avg_sleep_score': avg_sleep_score}},
        'condition_breakdown': condition_breakdown,
        'ai_insights': insights,
        'risk_level': risk_level,
    }
    from users.services.weekly_report_ai import generate_weekly_recommendations

    ai_recommendations = generate_weekly_recommendations(user, draft_payload)

    return {
        'wellbeing_snapshot': wellbeing_snapshot,
        'user': {
            'full_name': f'{user.first_name} {user.last_name}'.strip() or user.username,
            'user_id': user.id,
            'age': None,
            'gender': None,
            'report_period': f'{start_day.isoformat()} to {end_day.isoformat()}',
            'generated_date': timezone.now().isoformat(),
            'confidence_score': confidence_score,
        },
        'seven_day_data': day_reports,
        'analytics': {
            'labels': [d['date'] for d in day_reports],
            'stress_trend': stress_trend,
            'mood_stability_trend': mood_stability_trend,
            'screen_time_hours': screen_time_trend,
            'social_media_hours': social_trend,
            'late_night_usage_hours': late_night_trend,
            'depression_trend': depression_trend,
            'sleep_tracking': {
                'tracked_nights': tracked_sleep_nights,
                'total_late_night_hours': round(total_late_night_sec / 3600.0, 2),
                'daily': [
                    {
                        'date': d['date'],
                        'sleep_hours': d.get('sleep_time_hours'),
                        'sleep_tracked': d.get('sleep_data_source') == 'screen_time_table',
                        'late_night_hours': round(
                            int(d.get('late_night_usage_seconds') or 0) / 3600.0,
                            2,
                        ),
                    }
                    for d in day_reports
                ],
            },
            'app_usage_distribution_seconds': app_distribution,
            'progress_cards': {
                'avg_screen_time': _seconds_to_hm(avg_screen_seconds),
                'avg_sleep_score': avg_sleep_score,
                'productivity_score': avg_productivity,
                'emotional_stability_score': emotional_stability,
            },
            'weekly_comparison': {
                'previous_week_avg_screen_time': _seconds_to_hm(previous_avg_screen),
                'improvement_percentage': improvement_pct,
                'trend_arrow': 'up' if improvement_pct >= 0 else 'down',
            },
            'content_type_top3': (chunk_analytics.get('content_preference_top3') or {}).get('items') or [],
            'content_type_daily': chunk_analytics.get('content_type_daily') or [],
            'chunk_screen_time': chunk_analytics.get('screen_time') or {},
            'mental_health_summary': (chunk_analytics.get('mental_health') or {}).get('summary_message'),
        },
        'ai_insights': insights if include_premium_insights else [],
        'risk_level': risk_level,
        'mood_weekly': mood_weekly,
        'condition_breakdown': condition_breakdown,
        'chunk_analytics': chunk_analytics,
        'recommendations': ai_recommendations,
    }


def build_and_save_weekly_report(user: User, *, end_day: date | None = None) -> UserWeeklyReport:
    """Persist the rolling 7-day report for one user."""
    from users.services.sqlite_helpers import run_with_sqlite_retry

    def _save() -> UserWeeklyReport:
        start_day, end_day_resolved, _ = _current_week_bounds(end_day)
        payload = build_seven_day_report_payload(user, end_day=end_day_resolved)
        row, _ = UserWeeklyReport.objects.update_or_create(
            user=user,
            week_start=start_day,
            defaults={
                'week_end': end_day_resolved,
                'payload': payload,
            },
        )
        from users.services.mood_weekly_service import prune_old_weekly_reports

        prune_old_weekly_reports(user, keep=2, exclude_ids=[row.id])
        return row

    return run_with_sqlite_retry(_save)
