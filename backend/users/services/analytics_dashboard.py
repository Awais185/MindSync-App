"""Single payload for Analytics tab (day / week / month)."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, time, timedelta

from django.db.models import Sum
from django.utils import timezone

from tracking.models import ScreenTime
from tracking.services.screentime_rollup import day_total_seconds
from users.models import ScreenUsageEvent, VideoChunkAnalysis
from users.services.mood_weekly_service import _mood_label_from_json, _mood_score_from_label
from users.wellbeing import build_wellness_dashboard


def _period_days(period: str) -> int:
    if period == 'day':
        return 1
    if period == 'month':
        return 30
    return 7


def _window(period: str):
    days_n = _period_days(period)
    end_day = timezone.localdate()
    start_day = end_day - timedelta(days=max(0, days_n - 1))
    tz = timezone.get_current_timezone()
    start_at = timezone.make_aware(datetime.combine(start_day, time.min), tz)
    end_at = timezone.now()
    day_list = [start_day + timedelta(days=i) for i in range(days_n)]
    return period, days_n, start_day, end_day, start_at, end_at, day_list


def _fmt_duration_minutes(total_min: int) -> str:
    total_min = max(0, int(total_min))
    h = total_min // 60
    m = total_min % 60
    if h <= 0:
        return f'{m}m'
    return f'{h}h {m:02d}m'


def _fmt_duration_seconds(total_sec: int) -> str:
    return _fmt_duration_minutes((total_sec + 59) // 60)


def _sleep_minutes_for_period(user, period: str, end_day, day_list) -> int:
    """Sleep from ScreenTime.sleep_time (10 PM–6 AM window), aggregated by filter."""
    if period == 'day':
        for d in (end_day, end_day - timedelta(days=1)):
            row = ScreenTime.objects.filter(user=user, date=d).first()
            if row and row.sleep_time:
                return int(row.sleep_time) // 60
        return 0

    mins: list[int] = []
    for d in day_list:
        row = ScreenTime.objects.filter(user=user, date=d).first()
        if row and row.sleep_time:
            mins.append(int(row.sleep_time) // 60)
    if not mins:
        return 0
    return int(round(sum(mins) / len(mins)))


def _avg_daily_screen_seconds(user, period: str, day_list) -> int:
    if not day_list:
        return 0
    totals = [day_total_seconds(user, d) for d in day_list]
    if period == 'day':
        return totals[-1] if totals else 0
    return int(sum(totals) / len(totals))


def _mood_score_period(user, start_at, end_at) -> tuple[int, str]:
    from face_detection.models import FaceMoodScan

    scans = FaceMoodScan.objects.filter(
        user=user,
        created_at__gte=start_at,
        created_at__lte=end_at,
    ).order_by('-created_at')[:500]
    scores: list[float] = []
    for scan in scans:
        label = _mood_label_from_json(getattr(scan, 'mood', None))
        scores.append(_mood_score_from_label(label))
    if not scores:
        chunks = VideoChunkAnalysis.objects.filter(
            user=user,
            created_at__gte=start_at,
            created_at__lte=end_at,
        )[:300]
        for c in chunks:
            ct = c.content_type or {}
            mood = (ct.get('main_emotion') or ct.get('emotion') or 'neutral').strip().lower()
            scores.append(_mood_score_from_label(mood))
    if not scores:
        return 0, 'No mood logs yet'
    avg = sum(scores) / len(scores)
    score = int(round(avg * 100))
    if score >= 70:
        caption = 'Positive & steady'
    elif score >= 45:
        caption = 'Mixed signals'
    else:
        caption = 'Needs support'
    return score, caption


def _mental_averages(user, start_at, end_at) -> tuple[float, float, float]:
    from users.mental_health_scoring import compute_mental_health_scores

    chunks = list(
        VideoChunkAnalysis.objects.filter(
            user=user,
            created_at__gte=start_at,
            created_at__lte=end_at,
        )
    )
    stress_vals: list[float] = []
    anx_vals: list[float] = []
    dep_vals: list[float] = []
    for c in chunks:
        ct = c.content_type or {}
        mh = float(ct.get('mental_health_score') or 0)
        rk = float(ct.get('risk_score') or 0)
        if mh > 0:
            stress_vals.append(min(100.0, mh * 0.85 + rk * 0.15))
            anx_vals.append(min(100.0, mh * 0.75 + rk * 0.25))
            dep_vals.append(min(100.0, mh))
    if stress_vals:
        return (
            round(sum(stress_vals) / len(stress_vals), 1),
            round(sum(anx_vals) / len(anx_vals), 1),
            round(sum(dep_vals) / len(dep_vals), 1),
        )
    window_days = max(1, (end_at - start_at).days + 1)
    mh = compute_mental_health_scores(user, window_days=window_days)
    if mh.get('has_data'):
        anx = mh.get("anxiety") or {}
        return (
            float(mh["stress"]["score"]),
            float(anx.get("score") or 0),
            float(mh["depression"]["score"]),
        )
    return 0.0, 0.0, 0.0


def _night_window_for_anchor(anchor_date):
    tz = timezone.get_current_timezone()
    start = timezone.make_aware(datetime.combine(anchor_date, time(22, 0)), tz)
    end = timezone.make_aware(
        datetime.combine(anchor_date + timedelta(days=1), time(6, 0)),
        tz,
    )
    return start, end


_SOCIAL_KEYWORDS = (
    'tiktok',
    'instagram',
    'facebook',
    'snapchat',
    'twitter',
    'whatsapp',
    'reddit',
    'discord',
    'social',
)


def _is_social_app(package_name: str, app_name: str) -> bool:
    blob = f'{package_name} {app_name}'.lower()
    return any(k in blob for k in _SOCIAL_KEYWORDS)


def _late_night_stats(user, day_list) -> dict:
    total_sec = 0
    social_sec = 0
    by_app: dict[str, int] = defaultdict(int)
    tz = timezone.get_current_timezone()

    for d in day_list:
        row = ScreenTime.objects.filter(user=user, date=d).first()
        if row and row.late_night_activity:
            total_sec += int(row.late_night_activity)

        night_start, night_end = _night_window_for_anchor(d)
        events = ScreenUsageEvent.objects.filter(
            user=user,
            end_time__gt=night_start,
            start_time__lt=night_end,
        )
        for ev in events:
            overlap_start = max(ev.start_time, night_start)
            overlap_end = min(ev.end_time, night_end)
            if overlap_end <= overlap_start:
                continue
            sec = int((overlap_end - overlap_start).total_seconds())
            if sec <= 0:
                continue
            by_app[ev.app_name or ev.package_name] += sec
            if _is_social_app(ev.package_name, ev.app_name):
                social_sec += sec

    if by_app:
        event_total = sum(by_app.values())
        if event_total > total_sec:
            total_sec = event_total
    elif total_sec == 0:
        pass

    top_name = ''
    top_sec = 0
    if by_app:
        top_name, top_sec = max(by_app.items(), key=lambda x: x[1])

    return {
        'total_seconds': int(total_sec),
        'social_media_seconds': int(social_sec if social_sec else 0),
        'top_app_name': top_name,
        'top_app_seconds': int(top_sec),
    }


def _rhythm_last_seven_days(user) -> dict:
    today = timezone.localdate()
    labels: list[str] = []
    hours: list[float] = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        labels.append(d.strftime('%a'))
        sec = day_total_seconds(user, d)
        hours.append(round(sec / 3600.0, 2))
    peak_idx = hours.index(max(hours)) if hours else 0
    return {
        'labels': labels,
        'hours_per_day': hours,
        'peak_day_label': labels[peak_idx] if labels else '',
    }


def _wellbeing_trend_pct(user, period: str, current_score: int) -> int | None:
    """Optional delta vs the immediately preceding window of equal length."""
    if current_score <= 0:
        return None
    days = _period_days(period)
    end_day = timezone.localdate()
    prior_end = end_day - timedelta(days=days)
    prior_start = prior_end - timedelta(days=max(0, days - 1))
    tz = timezone.get_current_timezone()
    prior_start_at = timezone.make_aware(
        datetime.combine(prior_start, time.min),
        tz,
    )
    prior_end_at = timezone.make_aware(
        datetime.combine(prior_end, time.max),
        tz,
    )
    chunks = VideoChunkAnalysis.objects.filter(
        user=user,
        created_at__gte=prior_start_at,
        created_at__lte=prior_end_at,
    )
    if not chunks.exists():
        return None
    sent_vals: list[float] = []
    mh_vals: list[float] = []
    for c in chunks:
        ct = c.content_type or {}
        sent_vals.append(float(ct.get('sentiment_score') or 50))
        mh_vals.append(float(ct.get('mental_health_score') or 0))
    if not sent_vals:
        return None
    avg_sent = sum(sent_vals) / len(sent_vals)
    avg_mh = sum(mh_vals) / len(mh_vals) if mh_vals else 0
    distress = avg_mh / 100.0
    prior_score = int(round(max(0, min(100, avg_sent * (1 - distress * 0.85)))))
    return current_score - prior_score


def _insights_block(user, period: str, start_at, end_at) -> dict:
    from users.services.behavioral_insights_analytics import build_unified_behavioral_insights

    window_days = _period_days(period)
    unified = build_unified_behavioral_insights(
        user,
        start_at,
        end_at,
        window_days=window_days,
    )
    return {
        'behaviour_study': unified.get('behaviour_study') or {},
        'facial_expression_study': unified.get('facial_expression_study') or {},
        'content_type_analysis': unified.get('content_type_analysis') or {},
    }


def build_analytics_dashboard(user, period: str = 'week') -> dict:
    period = (period or 'week').strip().lower()
    if period not in {'day', 'week', 'month'}:
        period = 'week'

    _, days_n, start_day, end_day, start_at, end_at, day_list = _window(period)
    report_days = 7 if period == 'week' else days_n
    wellness_report = build_wellness_dashboard(user, days=report_days)
    wellness_home = build_wellness_dashboard(user, days=3)
    wellbeing = int(wellness_report.get('wellbeing_score') or 0)
    mh = wellness_home.get('mental_health') or {}
    if mh.get('has_data'):
        stress = float(mh['stress']['score'])
        depression = float(mh['depression']['score'])
    else:
        stress = float(wellness_home.get('stress_indicator') or 0)
        depression = float(wellness_home.get('depression_indicator') or 0)
    from users.openface_home_metrics import latest_predicted_emotion

    latest_emotion = latest_predicted_emotion(user)

    sleep_min = _sleep_minutes_for_period(user, period, end_day, day_list)
    mood_score, mood_caption = _mood_score_period(user, start_at, end_at)
    avg_screen = _avg_daily_screen_seconds(user, period, day_list)
    late = _late_night_stats(user, day_list)
    rhythm = _rhythm_last_seven_days(user)
    trend = _wellbeing_trend_pct(user, period, wellbeing)

    period_labels = {
        'day': 'Today',
        'week': 'Last 7 days',
        'month': 'Last 30 days',
    }

    return {
        'period': period,
        'days_in_period': days_n,
        'period_label': period_labels.get(period, ''),
        'mindsync_index': {
            'wellbeing_score': wellbeing,
            'stress_avg': stress,
            'depression_avg': depression,
            'latest_emotion': latest_emotion,
            'trend_points_vs_prior': trend,
        },
        'behavior': {
            'sleep_minutes': sleep_min,
            'sleep_display': _fmt_duration_minutes(sleep_min),
            'mood_score': mood_score,
            'mood_caption': mood_caption,
            'avg_daily_screen_seconds': avg_screen,
            'avg_daily_screen_display': _fmt_duration_seconds(avg_screen),
        },
        'rhythm': rhythm,
        'late_night_activity': {
            **late,
            'total_display': _fmt_duration_seconds(late['total_seconds']),
            'social_display': _fmt_duration_seconds(late['social_media_seconds']),
            'top_app_display': _fmt_duration_seconds(late['top_app_seconds']),
            'period_label': period_labels.get(period, ''),
        },
        'insights': _insights_block(user, period, start_at, end_at),
    }
