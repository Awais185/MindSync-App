"""Unified Behaviour Study, Facial Expression Study, and Content Type analytics."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta
from typing import Any

from django.utils import timezone

BEHAVIOUR_CLASS_SPECS: tuple[tuple[str, str], ...] = (
    ('stress', 'Stress'),
    ('anxiety', 'Anxiety'),
    ('depression', 'Depression'),
    ('suicidal_thoughts', 'Suicidal Thoughts'),
)

FACIAL_CLASS_SPECS: tuple[tuple[str, str], ...] = (
    ('stress', 'Stress'),
    ('anxiety', 'Anxiety'),
    ('depression', 'Depression'),
    ('neutral', 'Normal'),
)

FACIAL_CONFIDENCE_MIN = 0.50


def _extract_state_probabilities(payload: dict | None) -> dict[str, float]:
    if not isinstance(payload, dict):
        return {}
    raw = payload.get('state_probabilities')
    if not isinstance(raw, dict):
        return {}
    out: dict[str, float] = {}
    for key, val in raw.items():
        try:
            out[str(key).strip().lower()] = float(val)
        except (TypeError, ValueError):
            continue
    return out


def _normalize_content_label(raw: str) -> str:
    text = (raw or '').strip()
    if not text:
        return 'Unknown'
    return text


def _extract_content_type_labels(content_type: dict | None) -> list[str]:
    """Read watched content types from VideoChunkAnalysis.content_type JSON."""
    if not isinstance(content_type, dict) or not content_type:
        return []

    labels: list[str] = []
    for key in ('content_type', 'category', 'content_category'):
        value = content_type.get(key)
        if isinstance(value, str) and value.strip():
            labels.append(value.strip())

    raw_labels = content_type.get('labels')
    if isinstance(raw_labels, list):
        for item in raw_labels:
            if isinstance(item, str) and item.strip():
                labels.append(item.strip())

    main = content_type.get('main_emotion') or content_type.get('emotion')
    if isinstance(main, str) and main.strip():
        labels.append(main.strip())

    seen: set[str] = set()
    unique: list[str] = []
    for label in labels:
        key = label.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(_normalize_content_label(label))
    return unique


def _video_chunks_in_range(user, start_at, end_at, *, strict: bool = False):
    """Return analysed chunks in [start_at, end_at]. Optional fallback for empty analytics windows."""
    from users.models import VideoChunkAnalysis

    ranged = VideoChunkAnalysis.objects.filter(
        user=user,
        created_at__gte=start_at,
        created_at__lte=end_at,
    )
    if strict or ranged.exists():
        return ranged
    return VideoChunkAnalysis.objects.filter(user=user)


def _extract_primary_content_label(content_type: dict | None) -> str | None:
    """Single watched content label per chunk (avoids double-counting multi-label rows)."""
    if not isinstance(content_type, dict) or not content_type:
        return None
    for key in ('content_type', 'category', 'content_category'):
        value = content_type.get(key)
        if isinstance(value, str) and value.strip():
            return _normalize_content_label(value.strip())
    raw_labels = content_type.get('labels')
    if isinstance(raw_labels, list):
        for item in raw_labels:
            if isinstance(item, str) and item.strip():
                return _normalize_content_label(item.strip())
    return None


_POSITIVE_EMOTIONS = frozenset(
    {'happy', 'joy', 'positive', 'calm', 'content', 'excited', 'pleasant'}
)
_NEGATIVE_EMOTIONS = frozenset(
    {'sad', 'angry', 'fear', 'disgust', 'negative', 'stressed', 'anxious', 'depressed'}
)


def _emotion_valence(emotion: str) -> str:
    text = (emotion or '').strip().lower()
    if not text or text in {'neutral', 'normal', 'unknown'}:
        return 'neutral'
    if text in _POSITIVE_EMOTIONS:
        return 'positive'
    if text in _NEGATIVE_EMOTIONS:
        return 'negative'
    return 'neutral'


def _chunk_condition_scores(row) -> dict[str, float | None]:
    """Derive stress / anxiety / depression percentages from one VideoChunkAnalysis row."""
    scores: dict[str, float | None] = {'stress': None, 'anxiety': None, 'depression': None}
    behavior_blob = row.behavior_results if isinstance(row.behavior_results, dict) else {}
    outputs = behavior_blob.get('classification_outputs') or row.classification_outputs or {}
    if not isinstance(outputs, dict):
        outputs = {}
    probs = outputs.get('probabilities') or {}
    if isinstance(probs, dict) and probs:
        for key in ('stress', 'anxiety', 'depression'):
            try:
                val = float(probs.get(key) or 0.0)
            except (TypeError, ValueError):
                val = 0.0
            if val > 0:
                scores[key] = round(val * 100.0, 1) if val <= 1 else round(val, 1)
        return scores

    slug = _behavior_slug_from_chunk_row(row)
    slug_scores = {
        'stress': 72.0,
        'anxiety': 68.0,
        'depression': 65.0,
        'suicidal_thoughts': 88.0,
    }
    if slug:
        base = slug_scores.get(slug, 60.0)
        if slug == 'stress':
            scores['stress'] = base
            scores['anxiety'] = round(base * 0.9, 1)
        elif slug == 'anxiety':
            scores['anxiety'] = base
            scores['stress'] = round(base * 0.85, 1)
        elif slug in {'depression', 'suicidal_thoughts'}:
            scores['depression'] = base
            scores['anxiety'] = round(base * 0.88, 1)
    return scores


def _seconds_to_hm(total_seconds: int) -> str:
    total_seconds = max(0, int(total_seconds))
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    return f'{h}h {m:02d}m'


def _day_window_bounds(start_day: date, end_day: date) -> tuple[datetime, datetime]:
    tz = timezone.get_current_timezone()
    start_at = timezone.make_aware(datetime.combine(start_day, time.min), tz)
    end_at = timezone.make_aware(datetime.combine(end_day + timedelta(days=1), time.min), tz)
    return start_at, end_at


def _behavior_result_slug(raw: str) -> str | None:
    text = (raw or '').strip().lower()
    if not text:
        return None
    if text in {'normal', 'unavailable', 'unknown', 'other'}:
        return None
    if 'suicid' in text:
        return 'suicidal_thoughts'
    if 'depress' in text:
        return 'depression'
    if 'anxiet' in text:
        return 'anxiety'
    if 'stress' in text:
        return 'stress'
    return None


def _behavior_slug_from_chunk_row(row) -> str | None:
    behavior_blob = row.behavior_results if isinstance(row.behavior_results, dict) else {}
    primary = str(
        row.behavior_result
        or behavior_blob.get('behavior_result')
        or ''
    ).strip()

    slug = _behavior_result_slug(primary)
    if slug:
        return slug
    if primary.lower() == 'normal':
        return None

    outputs = behavior_blob.get('classification_outputs') or row.classification_outputs or {}
    if not isinstance(outputs, dict):
        return None

    top_predictions = outputs.get('top_predictions') or []
    if isinstance(top_predictions, list):
        for item in top_predictions:
            if not isinstance(item, dict):
                continue
            label = str(item.get('label') or '').strip()
            try:
                score = float(item.get('score') or 0.0)
            except (TypeError, ValueError):
                score = 0.0
            if score < 0.5:
                continue
            mapped = _behavior_result_slug(label)
            if mapped:
                return mapped

    probs = outputs.get('probabilities') or {}
    if isinstance(probs, dict):
        best_slug = None
        best_score = -1.0
        for label, score in probs.items():
            mapped = _behavior_result_slug(str(label))
            if not mapped:
                continue
            try:
                val = float(score)
            except (TypeError, ValueError):
                continue
            if val >= 0.5 and val > best_score:
                best_score = val
                best_slug = mapped
        return best_slug

    return None


def build_behaviour_study(user, start_at, end_at, *, window_days: int) -> dict[str, Any]:
    from users.models import VideoChunkAnalysis

    counts: dict[str, int] = {slug: 0 for slug, _ in BEHAVIOUR_CLASS_SPECS}
    rows_scanned = 0

    qs = _video_chunks_in_range(user, start_at, end_at).only(
        'behavior_result',
        'behavior_results',
        'classification_outputs',
    )

    for row in qs.iterator():
        behavior_blob = row.behavior_results if isinstance(row.behavior_results, dict) else {}
        has_behavior_data = bool(
            (row.behavior_result or '').strip()
            or behavior_blob
            or row.classification_outputs
        )
        if not has_behavior_data:
            continue

        rows_scanned += 1
        slug = _behavior_slug_from_chunk_row(row)
        if slug:
            counts[slug] += 1

    total_hits = sum(counts.values())
    cards = []
    for slug, label in BEHAVIOUR_CLASS_SPECS:
        count = int(counts.get(slug) or 0)
        cards.append(
            {
                'key': slug,
                'label': label,
                'count': count,
                'percent': 0.0,
                'average_per_day': 0.0,
                'status': 'Not Detected',
            }
        )

    if total_hits <= 0:
        return {
            'has_data': rows_scanned > 0,
            'records_analyzed': rows_scanned,
            'classes': cards,
        }

    for card in cards:
        count = int(card['count'])
        card['percent'] = round((count / total_hits) * 100.0, 1)
        card['average_per_day'] = round(count / max(1, window_days), 2)
        card['status'] = 'Detected' if count > 0 else 'Not Detected'

    return {
        'has_data': rows_scanned > 0,
        'records_analyzed': rows_scanned,
        'classes': cards,
    }


def build_facial_expression_study(user, start_at, end_at) -> dict[str, Any]:
    from face_detection.models import FaceAnalysis, FacialExpressionCapture

    total_by_class: dict[str, int] = {slug: 0 for slug, _ in FACIAL_CLASS_SPECS}
    valid_by_class: dict[str, int] = {slug: 0 for slug, _ in FACIAL_CLASS_SPECS}
    records = 0

    def _accumulate(probs: dict[str, float]) -> None:
        nonlocal records
        if not probs:
            return
        records += 1
        for slug, _ in FACIAL_CLASS_SPECS:
            try:
                val = float(probs.get(slug) or 0.0)
            except (TypeError, ValueError):
                val = 0.0
            if slug == 'neutral':
                val = max(val, float(probs.get('normal') or 0.0))
            if val > 0:
                total_by_class[slug] += 1
            if val > FACIAL_CONFIDENCE_MIN:
                valid_by_class[slug] += 1

    captures = FacialExpressionCapture.objects.filter(
        user=user,
        status=FacialExpressionCapture.STATUS_COMPLETED,
        created_at__gte=start_at,
        created_at__lte=end_at,
    ).only('au_results')

    for cap in captures.iterator():
        au = cap.au_results if isinstance(cap.au_results, dict) else {}
        probs = _extract_state_probabilities(au)
        if not probs and au:
            probs = {
                'stress': float(au.get('stress_score') or 0) / 100.0,
                'anxiety': float(au.get('anxiety_score') or 0) / 100.0,
                'depression': float(au.get('depression_score') or 0) / 100.0,
            }
            dom = str(au.get('dominant_state') or '').lower()
            if dom in {'neutral', 'normal', ''}:
                probs['neutral'] = max(probs.get('neutral', 0.0), 0.55)
        _accumulate(probs)

    analyses = FaceAnalysis.objects.filter(
        user=user,
        created_at__gte=start_at,
        created_at__lte=end_at,
    ).only('openface_payload', 'stress_score', 'anxiety_score', 'depression_score', 'emotion_label')

    for row in analyses.iterator():
        payload = row.openface_payload if isinstance(row.openface_payload, dict) else {}
        probs = _extract_state_probabilities(payload)
        if not probs:
            probs = {
                'stress': float(row.stress_score or 0) / 100.0,
                'anxiety': float(row.anxiety_score or 0) / 100.0,
                'depression': float(row.depression_score or 0) / 100.0,
            }
            em = str(row.emotion_label or '').lower()
            if em in {'neutral', 'normal', ''}:
                probs['neutral'] = max(probs.get('neutral', 0.0), 0.55)
        _accumulate(probs)

    valid_total = sum(valid_by_class.values())
    cards = []
    for slug, label in FACIAL_CLASS_SPECS:
        total_det = int(total_by_class.get(slug) or 0)
        valid_det = int(valid_by_class.get(slug) or 0)
        percent = round((valid_det / valid_total) * 100.0, 1) if valid_total else 0.0
        cards.append(
            {
                'key': slug,
                'label': label,
                'total_detections': total_det,
                'valid_detections': valid_det,
                'percent': percent,
            }
        )

    return {
        'has_data': records > 0,
        'records_analyzed': records,
        'confidence_threshold': FACIAL_CONFIDENCE_MIN,
        'classes': cards,
    }


def build_content_type_analysis(
    user,
    start_at,
    end_at,
    *,
    strict: bool = False,
) -> dict[str, Any]:
    counts: Counter[str] = Counter()
    chunks_with_label = 0

    qs = _video_chunks_in_range(user, start_at, end_at, strict=strict).only('content_type')

    for row in qs.iterator():
        ct = row.content_type if isinstance(row.content_type, dict) else {}
        label = _extract_primary_content_label(ct)
        if not label:
            continue
        counts[label] += 1
        chunks_with_label += 1

    total = sum(counts.values())
    sorted_items = counts.most_common()
    top_three = {name for name, _ in sorted_items[:3]}
    items = []
    for name, count in sorted_items:
        percent = round((count / total) * 100.0, 1) if total else 0.0
        items.append(
            {
                'label': name,
                'count': int(count),
                'percent': percent,
                'is_top': name in top_three,
            }
        )

    return {
        'has_data': total > 0,
        'chunks_analyzed': chunks_with_label,
        'items': items,
    }


def build_content_type_daily_trend(
    user,
    start_at,
    end_at,
    days: list[date],
    *,
    strict: bool = True,
) -> list[dict[str, Any]]:
    counts_by_day: dict[date, Counter[str]] = defaultdict(Counter)
    qs = _video_chunks_in_range(user, start_at, end_at, strict=strict).only(
        'content_type',
        'created_at',
    )
    for row in qs.iterator():
        day = timezone.localtime(row.created_at).date()
        label = _extract_primary_content_label(
            row.content_type if isinstance(row.content_type, dict) else {}
        )
        if not label:
            continue
        counts_by_day[day][label] += 1

    trend: list[dict[str, Any]] = []
    for day in days:
        day_counts = counts_by_day.get(day, Counter())
        if not day_counts:
            trend.append(
                {
                    'date': day.isoformat(),
                    'has_data': False,
                    'top_label': None,
                    'top_count': 0,
                    'total_chunks': 0,
                    'message': 'No content data for this day',
                }
            )
            continue
        top_label, top_count = day_counts.most_common(1)[0]
        total = sum(day_counts.values())
        trend.append(
            {
                'date': day.isoformat(),
                'has_data': True,
                'top_label': top_label,
                'top_count': int(top_count),
                'total_chunks': int(total),
                'distribution': [
                    {
                        'label': name,
                        'count': int(count),
                        'percent': round((count / total) * 100.0, 1),
                    }
                    for name, count in day_counts.most_common()
                ],
            }
        )
    return trend


def build_chunk_screen_time_daily(
    user,
    start_at,
    end_at,
    days: list[date],
    *,
    strict: bool = True,
) -> dict[str, Any]:
    seconds_by_day: dict[date, int] = defaultdict(int)
    chunks_by_day: dict[date, int] = defaultdict(int)
    qs = _video_chunks_in_range(user, start_at, end_at, strict=strict).only(
        'created_at',
        'duration_seconds',
    )
    for row in qs.iterator():
        day = timezone.localtime(row.created_at).date()
        dur = int(row.duration_seconds or 0)
        if dur <= 0:
            dur = 0
        seconds_by_day[day] += dur
        chunks_by_day[day] += 1

    daily: list[dict[str, Any]] = []
    total_seconds = 0
    for day in days:
        sec = int(seconds_by_day.get(day, 0))
        chunk_count = int(chunks_by_day.get(day, 0))
        total_seconds += sec
        daily.append(
            {
                'date': day.isoformat(),
                'seconds': sec,
                'hours': round(sec / 3600.0, 2),
                'chunk_count': chunk_count,
                'has_data': sec > 0 or chunk_count > 0,
                'label': _seconds_to_hm(sec) if sec > 0 else 'No data',
            }
        )

    has_data = total_seconds > 0 or any(d['chunk_count'] > 0 for d in daily)
    return {
        'has_data': has_data,
        'total_seconds': total_seconds,
        'total_label': _seconds_to_hm(total_seconds) if total_seconds > 0 else 'No data',
        'daily': daily,
        'message': (
            'No screen time recorded from video chunks for this period.'
            if not has_data
            else None
        ),
    }


def build_chunk_mental_health_weekly(
    user,
    start_at,
    end_at,
    days: list[date],
    *,
    window_days: int = 7,
    strict: bool = True,
) -> dict[str, Any]:
    stress_by_day: dict[date, list[float]] = defaultdict(list)
    anxiety_by_day: dict[date, list[float]] = defaultdict(list)
    depression_by_day: dict[date, list[float]] = defaultdict(list)
    valence_counts: Counter[str] = Counter()

    qs = _video_chunks_in_range(user, start_at, end_at, strict=strict).only(
        'created_at',
        'content_type',
        'behavior_result',
        'behavior_results',
        'classification_outputs',
    )
    rows_scanned = 0
    for row in qs.iterator():
        rows_scanned += 1
        day = timezone.localtime(row.created_at).date()
        scores = _chunk_condition_scores(row)
        if scores['stress'] is not None:
            stress_by_day[day].append(float(scores['stress']))
        if scores['anxiety'] is not None:
            anxiety_by_day[day].append(float(scores['anxiety']))
        if scores['depression'] is not None:
            depression_by_day[day].append(float(scores['depression']))

        ct = row.content_type if isinstance(row.content_type, dict) else {}
        emotion = ct.get('main_emotion') or ct.get('emotion') or ''
        valence_counts[_emotion_valence(str(emotion))] += 1

    def _avg(values: list[float]) -> float | None:
        if not values:
            return None
        return round(sum(values) / len(values), 1)

    weekly_trend: list[dict[str, Any]] = []
    stress_all: list[float] = []
    anxiety_all: list[float] = []
    depression_all: list[float] = []

    for day in days:
        stress = _avg(stress_by_day.get(day, []))
        anxiety = _avg(anxiety_by_day.get(day, []))
        depression = _avg(depression_by_day.get(day, []))
        if stress is not None:
            stress_all.append(stress)
        if anxiety is not None:
            anxiety_all.append(anxiety)
        if depression is not None:
            depression_all.append(depression)
        weekly_trend.append(
            {
                'date': day.isoformat(),
                'stress': stress,
                'anxiety': anxiety,
                'depression': depression,
                'has_data': any(v is not None for v in (stress, anxiety, depression)),
            }
        )

    valence_total = sum(valence_counts.values()) or 0
    emotion_distribution = {
        key: {
            'count': int(valence_counts.get(key, 0)),
            'percent': round((valence_counts.get(key, 0) / valence_total) * 100.0, 1)
            if valence_total
            else 0.0,
        }
        for key in ('positive', 'neutral', 'negative')
    }

    behaviour_study = build_behaviour_study(user, start_at, end_at, window_days=window_days)
    facial_study = build_facial_expression_study(user, start_at, end_at)
    behaviour_insight = build_behaviour_insight(
        user,
        start_at,
        end_at,
        window_days=window_days,
    )

    has_chunk_scores = bool(stress_all or anxiety_all or depression_all)
    has_data = has_chunk_scores or behaviour_study.get('has_data') or facial_study.get('has_data')

    summary_message = 'No mental health data available for this period.'
    if behaviour_insight.get('has_data') and behaviour_insight.get('message'):
        summary_message = str(behaviour_insight['message'])
    elif facial_study.get('has_data'):
        detected = [
            row
            for row in (facial_study.get('classes') or [])
            if int(row.get('valid_detections') or 0) > 0
        ]
        if detected:
            top = max(detected, key=lambda row: float(row.get('percent') or 0))
            summary_message = (
                f"Facial analysis shows {top.get('label', 'patterns')} "
                f"at {top.get('percent', 0)}% this week."
            )
    elif has_chunk_scores:
        avg_stress = _avg(stress_all)
        summary_message = (
            f'Video chunk behaviour indicates average stress at {avg_stress}% this week.'
            if avg_stress is not None
            else 'Behaviour signals detected from analysed video chunks.'
        )

    return {
        'has_data': has_data,
        'records_analyzed': rows_scanned,
        'weekly_trend': weekly_trend,
        'averages': {
            'stress': _avg(stress_all),
            'anxiety': _avg(anxiety_all),
            'depression': _avg(depression_all),
        },
        'emotion_distribution': emotion_distribution,
        'behaviour_study': behaviour_study,
        'facial_expression_study': facial_study,
        'behaviour_insight': behaviour_insight,
        'summary_message': summary_message,
    }


def build_parent_content_monitor(user) -> dict[str, Any]:
    """All-time (or full chunk history) top-3 content types for Parent Control."""
    from users.models import VideoChunkAnalysis

    qs = VideoChunkAnalysis.objects.filter(user=user).only('content_type', 'created_at')
    if not qs.exists():
        return {
            'has_data': False,
            'items': [],
            'message': 'No content data available yet.',
        }
    earliest = qs.order_by('created_at').values_list('created_at', flat=True).first()
    start_at = earliest or (timezone.now() - timedelta(days=365))
    end_at = timezone.now()
    analysis = build_content_type_analysis(user, start_at, end_at, strict=True)
    items = (analysis.get('items') or [])[:3]
    return {
        'has_data': bool(items),
        'items': [
            {
                'category': item['label'],
                'label': item['label'],
                'count': item['count'],
                'percent': item['percent'],
            }
            for item in items
        ],
        'message': (
            'No content data available yet.'
            if not items
            else None
        ),
    }


def build_seven_day_chunk_analytics(
    user,
    *,
    start_day: date,
    end_day: date,
    days: list[date],
) -> dict[str, Any]:
    """Unified 7-day VideoChunkAnalysis payload for Report + Home consistency."""
    start_at, end_at = _day_window_bounds(start_day, end_day)
    window_days = max(1, len(days))

    content_type = build_content_type_analysis(user, start_at, end_at, strict=True)
    content_preference = build_content_preference_top3(user, start_at, end_at, strict=True)
    content_daily = build_content_type_daily_trend(user, start_at, end_at, days, strict=True)
    screen_time = build_chunk_screen_time_daily(user, start_at, end_at, days, strict=True)
    mental_health = build_chunk_mental_health_weekly(
        user,
        start_at,
        end_at,
        days,
        window_days=window_days,
        strict=True,
    )

    try:
        chunk_count = _video_chunks_in_range(user, start_at, end_at, strict=True).count()
    except Exception:
        chunk_count = 0

    return {
        'has_data': chunk_count > 0,
        'total_chunks': chunk_count,
        'window_start': start_day.isoformat(),
        'window_end': end_day.isoformat(),
        'content_type': content_type,
        'content_preference_top3': content_preference,
        'content_type_daily': content_daily,
        'screen_time': screen_time,
        'mental_health': mental_health,
    }


BEHAVIOUR_INSIGHT_MESSAGES: dict[str, str] = {
    'stress': 'Stress detected from behavioural patterns',
    'anxiety': 'Behavioural analysis indicates anxiety trends',
    'depression': 'Behavioural analysis indicates depression-related patterns',
    'suicidal_thoughts': 'Behavioural analysis flagged elevated concern signals',
}


def build_content_preference_top3(
    user,
    start_at,
    end_at,
    *,
    strict: bool = False,
) -> dict[str, Any]:
    analysis = build_content_type_analysis(user, start_at, end_at, strict=strict)
    items = (analysis.get('items') or [])[:3]
    return {
        'has_data': bool(items),
        'items': [
            {
                'category': item['label'],
                'count': item['count'],
                'percent': item['percent'],
            }
            for item in items
        ],
    }


def build_behaviour_insight(user, start_at, end_at, *, window_days: int) -> dict[str, Any]:
    study = build_behaviour_study(user, start_at, end_at, window_days=window_days)
    if not study.get('has_data'):
        return {
            'has_data': False,
            'message': 'No behavioural patterns recorded yet.',
            'dominant_key': None,
        }

    classes = study.get('classes') or []
    detected = [row for row in classes if int(row.get('count') or 0) > 0]
    if not detected:
        return {
            'has_data': True,
            'message': 'No significant behavioural indicators detected.',
            'dominant_key': None,
        }

    dominant = max(detected, key=lambda row: int(row.get('count') or 0))
    key = (dominant.get('key') or '').strip().lower()
    label = (dominant.get('label') or 'Unknown').strip()
    message = BEHAVIOUR_INSIGHT_MESSAGES.get(
        key,
        f'Behavioural analysis indicates {label.lower()} trends',
    )
    return {
        'has_data': True,
        'message': message,
        'dominant_key': key,
        'dominant_label': label,
        'count': int(dominant.get('count') or 0),
        'percent': float(dominant.get('percent') or 0.0),
    }


def build_unified_behavioral_insights(user, start_at, end_at, *, window_days: int) -> dict[str, Any]:
    return {
        'behaviour_study': build_behaviour_study(user, start_at, end_at, window_days=window_days),
        'facial_expression_study': build_facial_expression_study(user, start_at, end_at),
        'content_type_analysis': build_content_type_analysis(user, start_at, end_at),
    }
