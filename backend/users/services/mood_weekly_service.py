"""Rolling 7-day mood window: live aggregation, archive, and weekly UI payloads."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from face_detection.models import FaceMoodScan
from users.models import UserMoodWindow, UserWeeklyReport

_NEGATIVE_MOODS = frozenset(
    {'sad', 'fear', 'angry', 'disgust', 'anxious', 'anxiety', 'stressed', 'stress', 'depressed', 'neutral_negative'}
)
_POSITIVE_MOODS = frozenset(
    {'happy', 'joy', 'surprise', 'neutral', 'calm', 'content', 'relaxed'}
)

# Valence 0 = low (sad/negative), 1 = high (happy/positive) for graph Y-axis.
_MOOD_VALENCE: dict[str, float] = {
    'happy': 0.88,
    'joy': 0.92,
    'surprise': 0.72,
    'neutral': 0.50,
    'calm': 0.62,
    'content': 0.70,
    'relaxed': 0.68,
    'sad': 0.22,
    'fear': 0.18,
    'angry': 0.28,
    'disgust': 0.25,
    'anxious': 0.32,
    'depressed': 0.20,
    'stress': 0.35,
}


def _mood_category(label: str) -> str:
    low = label.lower().replace(' ', '_')
    if any(k in low for k in ('happy', 'joy', 'surprise', 'calm', 'content', 'relaxed')):
        return 'happy'
    if any(k in low for k in ('sad', 'fear', 'angry', 'disgust', 'anxious', 'depress', 'stress')):
        return 'sad'
    return 'neutral'


def _mood_score_from_label(label: str) -> float:
    if not label or label == 'Unknown':
        return 0.5
    low = label.lower().replace(' ', '_')
    for key, val in _MOOD_VALENCE.items():
        if key in low:
            return val
    return 0.5


def _graph_label(label: str) -> str:
    cat = _mood_category(label)
    return {'happy': 'Happy', 'sad': 'Sad', 'neutral': 'Neutral'}[cat]


def _first_preview_media(request, day_scans: list[FaceMoodScan]) -> dict[str, Any] | None:
    for scan in day_scans:
        for item in _absolute_media(request, scan):
            if item.get('type') == 'image':
                return item
    for scan in day_scans:
        media = _absolute_media(request, scan)
        if media:
            return media[0]
    return None


def _local_today() -> date:
    return timezone.localdate()


def get_or_init_mood_window(user: User) -> UserMoodWindow:
    today = _local_today()
    row, created = UserMoodWindow.objects.get_or_create(
        user=user,
        defaults={'window_start': today},
    )
    if created:
        return row
    return row


def window_bounds(window_start: date) -> tuple[date, date]:
    end = window_start + timedelta(days=6)
    return window_start, end


def _mood_label_from_json(mood: dict | None) -> str:
    if not isinstance(mood, dict):
        return 'Unknown'
    for key in ('prediction', 'dominant_emotion', 'emotion', 'label'):
        val = mood.get(key)
        if val:
            return str(val).replace('_', ' ').strip().title()
    em = mood.get('emotions')
    if isinstance(em, dict) and em:
        top = max(em, key=lambda k: float(em[k] or 0))
        return str(top).replace('_', ' ').strip().title()
    return 'Unknown'


def _stress_from_label(label: str) -> float:
    low = label.lower().replace(' ', '_')
    if any(n in low for n in _NEGATIVE_MOODS):
        if 'angry' in low or 'fear' in low:
            return 78.0
        if 'sad' in low or 'depress' in low:
            return 72.0
        return 65.0
    if any(p in low for p in _POSITIVE_MOODS):
        return 28.0
    return 45.0


def queryset_for_window(user: User, window_start: date, window_end: date):
    start_dt = timezone.make_aware(datetime.combine(window_start, time.min))
    end_dt = timezone.make_aware(datetime.combine(window_end + timedelta(days=1), time.min))
    return FaceMoodScan.objects.filter(
        user=user,
        matched=True,
        created_at__gte=start_dt,
        created_at__lt=end_dt,
    ).order_by('created_at')


def _absolute_media(request, scan: FaceMoodScan) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if scan.capture_image:
        url = scan.capture_image.url
        if request is not None:
            url = request.build_absolute_uri(url)
        items.append({'type': 'image', 'url': url, 'id': scan.id})
    if scan.capture_video:
        url = scan.capture_video.url
        if request is not None:
            url = request.build_absolute_uri(url)
        items.append({'type': 'video', 'url': url, 'id': scan.id})
    return items


def build_mood_insights(scans: list[FaceMoodScan]) -> dict[str, Any]:
    if not scans:
        return {
            'has_data': False,
            'entry_count': 0,
            'dominant_mood': 'neutral',
            'avg_stress': 0.0,
            'avg_anxiety': 0.0,
            'avg_depression': 0.0,
            'patterns': [],
        }
    labels = [_mood_label_from_json(s.mood) for s in scans]
    dominant = Counter(labels).most_common(1)[0][0]
    stress_vals = [_stress_from_label(l) for l in labels]
    avg_stress = sum(stress_vals) / len(stress_vals)
    avg_anxiety = avg_stress * 0.92
    avg_depression = avg_stress * 0.78 if any('sad' in l.lower() or 'depress' in l.lower() for l in labels) else avg_stress * 0.55
    patterns: list[str] = []
    if len(scans) >= 3:
        neg = sum(1 for l in labels if any(n in l.lower() for n in _NEGATIVE_MOODS))
        if neg >= len(labels) * 0.5:
            patterns.append('Negative moods cluster in your current window.')
        pos = sum(1 for l in labels if any(p in l.lower() for p in _POSITIVE_MOODS))
        if pos >= len(labels) * 0.5:
            patterns.append('Mostly positive mood signals this week.')
    return {
        'has_data': True,
        'entry_count': len(scans),
        'dominant_mood': dominant,
        'avg_stress': round(avg_stress, 1),
        'avg_anxiety': round(avg_anxiety, 1),
        'avg_depression': round(avg_depression, 1),
        'patterns': patterns,
    }


def build_weekly_mood_payload(user: User, request=None) -> dict[str, Any]:
    """Live weekly mood architecture + insights for home and reports."""
    window = get_or_init_mood_window(user)
    window_start, window_end = window_bounds(window.window_start)
    today = _local_today()
    effective_end = min(window_end, today)
    scans = list(queryset_for_window(user, window_start, effective_end))
    entry_count = len(scans)

    by_day: dict[date, list[FaceMoodScan]] = defaultdict(list)
    for scan in scans:
        by_day[timezone.localtime(scan.created_at).date()].append(scan)

    days_out: list[dict[str, Any]] = []
    d = window_start
    while d <= window_end:
        day_scans = by_day.get(d, [])
        if day_scans:
            labels = [_mood_label_from_json(s.mood) for s in day_scans]
            day_label = Counter(labels).most_common(1)[0][0]
            scores = [_mood_score_from_label(l) for l in labels]
            day_score = round(sum(scores) / len(scores), 3)
            preview = _first_preview_media(request, day_scans)
            media = [preview] if preview else []
        else:
            day_label = ''
            day_score = None
            media = []
        days_out.append(
            {
                'date': d.isoformat(),
                'label': day_label,
                'graph_label': _graph_label(day_label) if day_label else '',
                'mood_score': day_score,
                'mood_category': _mood_category(day_label) if day_label else '',
                'entries': len(day_scans),
                'media': media,
            }
        )
        d += timedelta(days=1)

    insights = build_mood_insights(scans)
    has_summary = entry_count >= 3
    dominant = insights['dominant_mood'] if has_summary else ''

    all_labels = [_mood_label_from_json(s.mood) for s in scans]
    all_scores = [_mood_score_from_label(l) for l in all_labels] if all_labels else []
    overall_score = round(sum(all_scores) / len(all_scores), 3) if all_scores else None
    overall_label = _graph_label(dominant) if dominant else ''
    overall_category = _mood_category(dominant) if dominant else ''

    cat_counts = Counter(_mood_category(l) for l in all_labels)
    total_l = len(all_labels) or 1
    mood_distribution = [
        {
            'mood': cat,
            'label': {'happy': 'Happy', 'sad': 'Sad', 'neutral': 'Neutral'}[cat],
            'count': cnt,
            'percent': round(100.0 * cnt / total_l, 1),
        }
        for cat, cnt in cat_counts.most_common()
    ]

    graph_series = [
        {
            'date': day['date'],
            'label': day.get('label') or '',
            'graph_label': day.get('graph_label') or '',
            'mood_score': day.get('mood_score'),
            'mood_category': day.get('mood_category') or '',
        }
        for day in days_out
    ]

    return {
        'window_start': window_start.isoformat(),
        'window_end': window_end.isoformat(),
        'days_in_window': (effective_end - window_start).days + 1,
        'entry_count': entry_count,
        'has_summary': has_summary,
        'placeholder': None if has_summary else 'Not enough data yet',
        'dominant_mood': dominant,
        'overall_mood': {
            'label': overall_label,
            'raw_label': dominant,
            'score': overall_score,
            'category': overall_category,
        },
        'mood_distribution': mood_distribution,
        'graph_series': graph_series,
        'days': days_out,
        'insights': insights,
        'updated_at': timezone.now().isoformat(),
    }


def maybe_archive_mood_window(user: User) -> bool:
    """
    When 7 full days have elapsed since window_start, persist report and reset window.
    Returns True if an archive occurred.
    """
    window = get_or_init_mood_window(user)
    today = _local_today()
    if (today - window.window_start).days < 7:
        return False

    window_start = window.window_start
    window_end = window_start + timedelta(days=6)
    from users.services.weekly_report_builder import build_seven_day_report_payload

    payload = build_seven_day_report_payload(user, end_day=window_end)
    payload['mood_weekly'] = build_weekly_mood_payload(user, request=None)

    from users.services.sqlite_helpers import run_with_sqlite_retry

    def _archive() -> UserWeeklyReport:
        row, _ = UserWeeklyReport.objects.update_or_create(
            user=user,
            week_start=window_start,
            defaults={
                'week_end': window_end,
                'payload': payload,
            },
        )
        prune_old_weekly_reports(user, keep=2, exclude_ids=[row.id])
        return row

    row = run_with_sqlite_retry(_archive)
    window.window_start = today
    window.save(update_fields=['window_start'])
    return True


def on_mood_scan_saved(user: User) -> None:
    """Called after a new FaceMoodScan is stored."""
    get_or_init_mood_window(user)
    maybe_archive_mood_window(user)


def prune_old_weekly_reports(
    user: User,
    *,
    keep: int = 2,
    exclude_ids: list[int] | None = None,
) -> int:
    """Keep only the newest [keep] reports; delete older rows (no file paths on model)."""
    exclude = set(exclude_ids or [])
    keep_ids = list(
        UserWeeklyReport.objects.filter(user=user)
        .order_by('-generated_at')
        .values_list('id', flat=True)[:keep]
    )
    stale = UserWeeklyReport.objects.filter(user=user).exclude(id__in=keep_ids)
    if exclude:
        stale = stale.exclude(id__in=exclude)
    deleted, _ = stale.delete()
    return deleted


def list_past_weekly_reports(user: User, limit: int = 2) -> list[dict[str, Any]]:
    rows = UserWeeklyReport.objects.filter(user=user).order_by('-generated_at')[:limit]
    return [
        {
            'id': r.id,
            'week_start': r.week_start.isoformat(),
            'week_end': r.week_end.isoformat(),
            'generated_at': r.generated_at.isoformat(),
            'has_payload': bool(r.payload),
        }
        for r in rows
    ]


def get_archived_report(user: User, report_id: int) -> UserWeeklyReport | None:
    return UserWeeklyReport.objects.filter(user=user, id=report_id).first()
