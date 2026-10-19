"""Per-day stress / anxiety / depression and screen–mood correlation for 7-day reports."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from tracking.models import ScreenTime
from users.mental_health_severity import severity_label_from_percent


def _clamp(val: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, val))


def _avg_int(values: list[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 1)


def build_seven_day_condition_breakdown(
    user: User,
    *,
    start_day: date,
    end_day: date,
    days: list[date],
    chunk_analytics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    from face_detection.models import FaceMoodScan, FacialExpressionCapture
    from users.services.mood_weekly_service import _mood_label_from_json

    screen_map = {r.date: r for r in ScreenTime.objects.filter(user=user, date__range=(start_day, end_day))}

    chunk_screen_by_day: dict[str, int] = {}
    chunk_trend_by_date: dict[str, dict[str, Any]] = {}
    if isinstance(chunk_analytics, dict):
        for row in (chunk_analytics.get('screen_time') or {}).get('daily') or []:
            if isinstance(row, dict) and row.get('date'):
                chunk_screen_by_day[str(row['date'])] = int(row.get('seconds') or 0)
        for row in (chunk_analytics.get('mental_health') or {}).get('weekly_trend') or []:
            if isinstance(row, dict) and row.get('date'):
                chunk_trend_by_date[str(row['date'])] = row

    facial_by_day: dict[date, list] = defaultdict(list)
    for row in FacialExpressionCapture.objects.filter(
        user=user,
        status=FacialExpressionCapture.STATUS_COMPLETED,
        created_at__date__range=(start_day, end_day),
    ):
        facial_by_day[timezone.localtime(row.created_at).date()].append(row)

    mood_by_day: dict[date, list] = defaultdict(list)
    start_dt = timezone.make_aware(datetime.combine(start_day, time.min))
    end_dt = timezone.make_aware(datetime.combine(end_day + timedelta(days=1), time.min))
    for scan in FaceMoodScan.objects.filter(
        user=user,
        matched=True,
        created_at__gte=start_dt,
        created_at__lt=end_dt,
    ):
        mood_by_day[timezone.localtime(scan.created_at).date()].append(scan)

    day_rows: list[dict[str, Any]] = []
    risk_alerts: list[dict[str, Any]] = []
    stress_all: list[float] = []
    depression_all: list[float] = []
    screen_mood_rows: list[dict[str, Any]] = []

    for i, d in enumerate(days):
        from users.openface_home_metrics import _label_from_capture

        stress_vals: list[float] = []
        depression_vals: list[float] = []
        emotion_labels: list[str] = []

        for fac in facial_by_day.get(d, []):
            if fac.stress_score is not None:
                stress_vals.append(float(fac.stress_score))
            if fac.depression_score is not None:
                depression_vals.append(float(fac.depression_score))
            em = (getattr(fac, "emotion", None) or "").strip()
            if not em:
                em = _label_from_capture(fac)
            if em and em.lower() not in {"awaiting scan", "neutral", ""}:
                emotion_labels.append(em.strip().title())
            elif em:
                emotion_labels.append(em.strip().title())

        for scan in mood_by_day.get(d, []):
            label = _mood_label_from_json(scan.mood)
            if label and label != 'Unknown':
                emotion_labels.append(label.strip().title())

        stress = _avg_int(stress_vals)
        depression = _avg_int(depression_vals)
        emotion = None
        if emotion_labels:
            emotion = Counter(emotion_labels).most_common(1)[0][0]

        chunk_row = chunk_trend_by_date.get(d.isoformat()) or {}
        if stress is None and chunk_row.get('stress') is not None:
            stress = float(chunk_row['stress'])
        if depression is None and chunk_row.get('depression') is not None:
            depression = float(chunk_row['depression'])

        screen_row = screen_map.get(d)
        screen_seconds = int(screen_row.total_screen_time) if screen_row else 0
        chunk_seconds = int(chunk_screen_by_day.get(d.isoformat(), 0))
        if chunk_seconds > 0:
            screen_seconds = chunk_seconds
        has_screen = screen_seconds > 0

        if stress is not None:
            stress_all.append(stress)
        if depression is not None:
            depression_all.append(depression)

        for cond, score in (
            ('Stress', stress),
            ('Depression', depression),
        ):
            if score is not None and score > 80:
                risk_alerts.append(
                    {
                        'condition': cond,
                        'day': i + 1,
                        'date': d.isoformat(),
                        'score': score,
                    }
                )

        day_rows.append(
            {
                'day': i + 1,
                'date': d.isoformat(),
                'stress': stress,
                'depression': depression,
                'emotion': emotion,
                'stress_label': severity_label_from_percent(stress),
                'depression_label': severity_label_from_percent(depression),
                'screen_time_seconds': screen_seconds,
                'screen_time_label': (
                    'No screen time recorded'
                    if not has_screen
                    else f'{screen_seconds // 3600}h {(screen_seconds % 3600) // 60}m'
                ),
            }
        )

        screen_mood_rows.append(
            {
                'date': d.isoformat(),
                'day': i + 1,
                'screen_hours': round(screen_seconds / 3600.0, 2) if has_screen else None,
                'screen_label': (
                    'No screen time recorded' if not has_screen else None
                ),
                'stress': stress,
                'depression': depression,
                'emotion': emotion,
                'dominant_mood': emotion,
            }
        )

    return {
        'days': day_rows,
        'averages': {
            'stress': _avg_int(stress_all),
            'depression': _avg_int(depression_all),
            'stress_label': severity_label_from_percent(_avg_int(stress_all)),
            'depression_label': severity_label_from_percent(_avg_int(depression_all)),
        },
        'risk_alerts': risk_alerts,
        'risk_summary': _format_risk_summary(risk_alerts),
        'screen_mood_correlation': screen_mood_rows,
    }


def _format_risk_summary(alerts: list[dict[str, Any]]) -> str:
    if not alerts:
        return 'No risk factors detected this week'
    by_cond: dict[str, list[int]] = defaultdict(list)
    for a in alerts:
        by_cond[a['condition']].append(int(a['day']))
    parts = []
    for cond, day_nums in sorted(by_cond.items()):
        days_str = ', '.join(f'Day {d}' for d in sorted(day_nums))
        parts.append(f'High {cond} detected on {days_str}')
    return '; '.join(parts)
