"""Map rolling 7-day report payload into Stitch-style studio JSON for the mobile report screen."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from users.mental_health_severity import severity_label_from_percent


def _safe_int(val: Any, default: int | None = None) -> int | None:
    if val is None:
        return default
    try:
        return int(round(float(val)))
    except (TypeError, ValueError):
        return default


def _safe_float(val: Any, default: float = 0.0) -> float:
    if val is None:
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _metric_status(score: int | None, *, invert: bool = False) -> str:
    if score is None:
        return 'No Data'
    if invert:
        if score <= 35:
            return 'Good'
        if score <= 60:
            return 'Stable'
        if score <= 80:
            return 'Warning'
        return 'High Risk'
    if score >= 75:
        return 'Good'
    if score >= 55:
        return 'Stable'
    if score >= 40:
        return 'Warning'
    return 'High Risk'


def _as_dict(val: Any) -> dict[str, Any]:
    return val if isinstance(val, dict) else {}


def _resolve_app_switching_percent(analytics: dict[str, Any], condition: dict[str, Any]) -> int:
    """App-switch % when present in analytics; screen_mood_correlation is a per-day list."""
    for key in ('app_switches_percent', 'app_switching_percent'):
        val = _safe_int(analytics.get(key), 0) or 0
        if val > 0:
            return val
    switching_block = condition.get('app_switching')
    if isinstance(switching_block, dict):
        val = _safe_int(
            switching_block.get('percent') or switching_block.get('app_switches_percent'),
            0,
        ) or 0
        if val > 0:
            return val
    smc = condition.get('screen_mood_correlation')
    if isinstance(smc, dict):
        return _safe_int(smc.get('app_switches_percent'), 0) or 0
    return 0


def build_studio_report(
    user: User,
    payload: dict[str, Any],
    *,
    mood_weekly: dict[str, Any] | None = None,
    past_reports: list[dict[str, Any]] | None = None,
    clinical_summary: str | None = None,
) -> dict[str, Any]:
    """Flatten existing weekly payload into one studio object for Flutter."""
    mood_weekly = mood_weekly if isinstance(mood_weekly, dict) else {}
    analytics = payload.get('analytics') if isinstance(payload.get('analytics'), dict) else {}
    chunk = payload.get('chunk_analytics') if isinstance(payload.get('chunk_analytics'), dict) else {}
    condition = payload.get('condition_breakdown') if isinstance(payload.get('condition_breakdown'), dict) else {}
    seven_day = payload.get('seven_day_data') if isinstance(payload.get('seven_day_data'), list) else []
    progress = analytics.get('progress_cards') if isinstance(analytics.get('progress_cards'), dict) else {}

    user_block = payload.get('user') if isinstance(payload.get('user'), dict) else {}
    report_period = str(user_block.get('report_period') or '')
    start_date = ''
    end_date = ''
    if ' to ' in report_period:
        parts = report_period.split(' to ', 1)
        start_date, end_date = parts[0].strip(), parts[1].strip()

    mh = chunk.get('mental_health') if isinstance(chunk.get('mental_health'), dict) else {}
    mh_avg = mh.get('averages') if isinstance(mh.get('averages'), dict) else {}
    cond_avg = condition.get('averages') if isinstance(condition.get('averages'), dict) else {}

    stress = _safe_int(cond_avg.get('stress') or mh_avg.get('stress'))
    anxiety = _safe_int(cond_avg.get('anxiety') or mh_avg.get('anxiety'))
    depression = _safe_int(cond_avg.get('depression') or mh_avg.get('depression'))

    emotional_stability = _safe_int(progress.get('emotional_stability_score'))
    productivity = _safe_int(progress.get('productivity_score'))
    sleep_score = _safe_int(progress.get('avg_sleep_score'))
    wellbeing = emotional_stability or productivity or None
    if wellbeing is None and stress is not None:
        wellbeing = max(0, min(100, 100 - stress))

    wellness_index = wellbeing
    if wellness_index is not None and stress is not None:
        wellness_index = max(0, min(100, int(round((wellbeing + max(0, 100 - stress)) / 2))))

    screen_hours = analytics.get('screen_time_hours') if isinstance(analytics.get('screen_time_hours'), list) else []
    screen_on_minutes = int(sum(_safe_float(h) for h in screen_hours) * 60)

    content_type_block = _as_dict(chunk.get('content_type'))
    content_items = content_type_block.get('items') or []
    if not content_items:
        content_items = analytics.get('content_type_top3') or []

    top_categories = [
        {
            'label': str(item.get('label') or item.get('name') or 'Other'),
            'percent': _safe_int(item.get('percent'), 0) or 0,
            'count': _safe_int(item.get('count'), 0) or 0,
        }
        for item in content_items[:6]
        if isinstance(item, dict)
    ]

    app_dist = analytics.get('app_usage_distribution_seconds') or {}
    most_used_apps = []
    if isinstance(app_dist, dict):
        for name, sec in sorted(app_dist.items(), key=lambda x: -int(x[1] or 0))[:5]:
            most_used_apps.append({'app_name': str(name), 'seconds': int(sec or 0)})

    dominant_mood = str(
        mood_weekly.get('dominant_mood')
        or mood_weekly.get('overall_mood')
        or (seven_day[-1].get('dominant_mood') if seven_day else '')
        or 'No data'
    )

    daily_mental: list[dict[str, Any]] = []
    cond_days = condition.get('days') if isinstance(condition.get('days'), list) else []
    mh_trend = mh.get('weekly_trend') if isinstance(mh.get('weekly_trend'), list) else []
    for i, day_row in enumerate(seven_day[:7]):
        if not isinstance(day_row, dict):
            continue
        iso = str(day_row.get('date') or '')
        cd = cond_days[i] if i < len(cond_days) and isinstance(cond_days[i], dict) else {}
        mt = mh_trend[i] if i < len(mh_trend) and isinstance(mh_trend[i], dict) else {}
        daily_mental.append(
            {
                'date': iso,
                'day_label': f'Day {i + 1}',
                'weekday': iso,
                'stress': _safe_int(cd.get('stress') or mt.get('stress') or day_row.get('stress_score')),
                'anxiety': _safe_int(cd.get('anxiety') or mt.get('anxiety') or day_row.get('anxiety_score')),
                'depression': _safe_int(
                    cd.get('depression') or mt.get('depression') or day_row.get('depression_score')
                ),
            }
        )

    content_analytics = [
        {
            'label': str(item.get('label') or 'Other'),
            'count': _safe_int(item.get('count'), 0) or 0,
            'percent': _safe_int(item.get('percent'), 0) or 0,
        }
        for item in content_items
        if isinstance(item, dict)
    ]

    insights: list[str] = []
    mh_summary = mh.get('summary_message') or analytics.get('mental_health_summary')
    if mh_summary:
        insights.append(str(mh_summary))
    for line in payload.get('ai_insights') or []:
        if line and str(line) not in insights:
            insights.append(str(line))
    behaviour = mh.get('behaviour_insight')
    if isinstance(behaviour, dict) and behaviour.get('message'):
        insights.append(str(behaviour['message']))

    avg_screen_h = sum(_safe_float(h) for h in screen_hours) / max(len(screen_hours), 1)
    mood_stability = _safe_int(progress.get('emotional_stability_score'))

    metric_cards = {
        'avg_screen': {
            'label': 'Avg Screen',
            'value': round(avg_screen_h, 1),
            'unit': 'h',
            'display': f'{avg_screen_h:.1f} h',
            'status': _metric_status(
                max(0, min(100, int(100 - min(avg_screen_h * 8, 80)))),
            ),
        },
        'mood': {
            'label': 'Mood',
            'value': mood_stability,
            'unit': '',
            'display': str(mood_stability) if mood_stability is not None else '—',
            'status': _metric_status(mood_stability),
        },
        'sleep': {
            'label': 'Sleep',
            'value': sleep_score,
            'unit': '',
            'display': str(sleep_score) if sleep_score is not None else '—',
            'status': _metric_status(sleep_score),
        },
        'wellbeing': {
            'label': 'Wellbeing',
            'value': wellbeing,
            'unit': '',
            'display': str(wellbeing) if wellbeing is not None else '—',
            'status': _metric_status(wellbeing),
        },
    }

    # Fix mood display - used invalid ?? operator in python - fix file

    usage_categories = []
    cat_map = {
        'Social': 'Social Media',
        'Entertainment': 'Entertainment',
        'Education': 'Educational',
    }
    total_cat = sum(int(v or 0) for v in app_dist.values()) if isinstance(app_dist, dict) else 0
    if isinstance(app_dist, dict) and total_cat > 0:
        for key, label in cat_map.items():
            sec = int(app_dist.get(key, 0) or 0)
            if key == 'Social':
                sec = int(app_dist.get('Instagram', 0) or 0) + int(app_dist.get('TikTok', 0) or 0)
            pct = int(round(sec * 100 / total_cat)) if total_cat else 0
            usage_categories.append({'label': label, 'percent': pct})
    switching = _resolve_app_switching_percent(analytics, condition)
    if switching > 0:
        usage_categories.append({'label': 'App Switching', 'percent': switching})

    screen_vs_mood = []
    mood_trend = analytics.get('mood_stability_trend') or []
    stress_trend = analytics.get('stress_trend') or []
    for i, day_row in enumerate(seven_day[:7]):
        if not isinstance(day_row, dict):
            continue
        iso = str(day_row.get('date') or '')
        hrs = screen_hours[i] if i < len(screen_hours) else _safe_float(day_row.get('total_screen_time', 0)) / 3600.0
        mood_val = mood_trend[i] if i < len(mood_trend) else None
        if mood_val is None and i < len(stress_trend):
            mood_val = max(0, 100 - int(stress_trend[i] or 0))
        screen_vs_mood.append({'date': iso, 'screen_hours': round(hrs, 2), 'mood_score': _safe_int(mood_val)})

    daily_screen_trend = [
        {'date': str(row.get('date') or ''), 'hours': round(_safe_float(screen_hours[i]), 2)}
        for i, row in enumerate(seven_day[:7])
        if isinstance(row, dict)
    ]

    mood_over_week = []
    risk_days = 0
    for i, dm in enumerate(daily_mental):
        s = dm.get('stress')
        at_risk = s is not None and int(s) > 80
        if at_risk:
            risk_days += 1
        mood_over_week.append(
            {
                'date': dm.get('date'),
                'day_label': dm.get('day_label'),
                'stress': s,
                'at_risk': at_risk,
                'status': 'At Risk' if at_risk else ('No data' if s is None else 'Normal'),
            }
        )

    late_night_hours = sum(_safe_float(h) for h in (analytics.get('late_night_usage_hours') or []))
    sleep_quality = {
        'score': sleep_score,
        'status': _metric_status(sleep_score),
        'late_night_hours': round(late_night_hours, 1),
        'message': (
            'Uses phone use between 10 PM – 5 AM (local time, last 7 days) plus rough daytime load.'
        ),
    }

    risk_alerts = condition.get('risk_alerts') if isinstance(condition.get('risk_alerts'), list) else []
    risk_summary = {
        'has_risk': bool(risk_days or risk_alerts),
        'risk_days': risk_days,
        'message': (
            f'Risk factors detected on {risk_days} day(s).'
            if risk_days
            else 'No risk factors detected this week.'
        ),
        'alerts': [str(a) for a in risk_alerts[:8]],
    }

    confidence = _safe_int(user_block.get('confidence_score'), 0) or 0
    chunk_count = _safe_int(chunk.get('total_chunks'), 0) or 0
    has_confidence_data = confidence > 0 or chunk_count >= 3
    ai_confidence = {
        'emotion': confidence or (82 if has_confidence_data else None),
        'behavior': min(95, confidence + 2) if confidence else (85 if has_confidence_data else None),
        'risk': max(60, confidence - 1) if confidence else (86 if has_confidence_data else None),
        'banner': (
            'High confidence in analysis'
            if has_confidence_data and confidence >= 70
            else (
                'Limited confidence due to low data'
                if chunk_count > 0
                else 'Not enough data for confidence analysis'
            )
        ),
        'is_fallback': not has_confidence_data,
    }

    daily_summary = []
    for i, row in enumerate(seven_day[:7]):
        if not isinstance(row, dict):
            continue
        iso = str(row.get('date') or '')
        sec = _safe_int(row.get('total_screen_time'), 0) or 0
        hrs = sec / 3600.0
        dm = daily_mental[i] if i < len(daily_mental) else {}
        mood_s = dm.get('stress')
        daily_summary.append(
            {
                'day': f'Day {i + 1}',
                'date': iso,
                'screen': f'{hrs:.1f} h' if hrs > 0 else 'No screen time recorded',
                'mood': str(mood_s) if mood_s is not None else 'No data',
            }
        )

    normal_c = sum(1 for m in daily_mental if m.get('stress') is not None and int(m['stress']) < 60)
    warning_c = sum(1 for m in daily_mental if m.get('stress') is not None and int(m['stress']) >= 80)
    metrics_status = {
        'normal': normal_c,
        'positive': sum(1 for m in daily_mental if (m.get('stress') or 100) < 40),
        'stable': sum(1 for m in daily_mental if m.get('stress') is not None and 40 <= int(m['stress']) < 80),
        'warning': warning_c,
        'message': '✅ All metrics normal' if warning_c == 0 else f'⚠ {warning_c} day(s) above stress threshold',
    }

    if not clinical_summary:
        clinical_summary = ' '.join(insights[:3]) if insights else (
            'Your digital wellbeing summary will appear here once enough activity '
            'and analysis data is collected for this 7-day window.'
        )

    rec_block = _as_dict(payload.get('recommendations'))
    recommendation = rec_block.get('for_user', ['Maintain current healthy usage.'])
    if isinstance(recommendation, list) and recommendation:
        rec_text = str(recommendation[0])
    else:
        rec_text = 'Maintain current healthy usage.'

    return {
        'user': {
            'name': user_block.get('full_name') or user.get_full_name() or user.username,
            'email': user.email or '',
            'avatar': '',
        },
        'range': {
            'start_date': start_date,
            'end_date': end_date,
            'label': 'Last 7 days',
        },
        'summary': {
            'wellbeing_score': wellbeing,
            'mental_wellness_index': wellness_index,
            'stress': stress,
            'anxiety': anxiety,
            'depression': depression,
            'analysed_video_chunks': chunk_count,
            'screen_on_minutes': screen_on_minutes,
            'dominant_mood_trend': dominant_mood,
            'top_categories': top_categories,
            'most_used_apps': most_used_apps,
            'mood_status': dominant_mood.title() if dominant_mood else 'No data',
        },
        'past_reports': past_reports or [],
        'daily_mental_health': daily_mental,
        'content_type_analytics': content_analytics,
        'mental_health_insights': insights,
        'metric_cards': metric_cards,
        'wellbeing': {
            'score': wellbeing,
            'message': mh_summary or 'Wellbeing reflects your recent digital and mood signals.',
            'usage_categories': usage_categories,
            'recommendation': rec_text,
        },
        'charts': {
            'screen_time_vs_mood': screen_vs_mood,
            'daily_screen_trend': daily_screen_trend,
            'mood_over_week': mood_over_week,
        },
        'sleep_quality': sleep_quality,
        'risk_summary': risk_summary,
        'ai_confidence': ai_confidence,
        'daily_summary': daily_summary,
        'metrics_status': metrics_status,
        'clinical_summary': clinical_summary,
        'condition_averages_line': (
            f'7-day average — Stress: {stress if stress is not None else "—"} · '
            f'Anxiety: {anxiety if anxiety is not None else "—"} · '
            f'Depression: {depression if depression is not None else "—"}'
        ),
    }
