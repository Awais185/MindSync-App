"""Per-user stress / anxiety / depression scores from facial + video chunk tables."""

from __future__ import annotations

import logging
from datetime import timedelta

from django.utils import timezone

logger = logging.getLogger(__name__)

HIGH_RISK_APPS = frozenset(
    {"tiktok", "instagram", "youtube", "snapchat"},
)

_EMOTIONS = ("stress", "anxiety", "depression")
MIN_EXPRESSIONS_REQUIRED = 5


def _completed_expression_count(user) -> int:
    from face_detection.models import FacialExpressionCapture

    return FacialExpressionCapture.objects.filter(
        user=user,
        status=FacialExpressionCapture.STATUS_COMPLETED,
    ).count()


def _clamp(value: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, value))


def _round1(value: float) -> float:
    return round(_clamp(value), 1)


def _trend(current: float, baseline: float) -> str:
    delta = current - baseline
    if delta > 5:
        return "up"
    if delta < -5:
        return "down"
    return "flat"


def _overall_level(score: float) -> tuple[str, str]:
    from users.mental_health_severity import severity_color_hex, severity_label_from_percent

    return severity_label_from_percent(score), severity_color_hex(score)


def _facial_emotion_score(rows, emotion: str, score_field: str) -> float:
    if not rows:
        return 0.0
    total = len(rows)
    dom_count = sum(
        1 for r in rows if (r.dominant_state or "").strip().lower() == emotion
    )
    dominance_rate = dom_count / total
    scores = [float(getattr(r, score_field) or 0) for r in rows]
    avg_score = sum(scores) / len(scores)

    cutoff = timezone.now() - timedelta(hours=24)
    recent = [r for r in rows if r.created_at and r.created_at > cutoff]
    if recent:
        recent_avg = sum(float(getattr(r, score_field) or 0) for r in recent) / len(recent)
    else:
        recent_avg = avg_score

    raw = (avg_score * 0.5 + dominance_rate * 100.0 * 0.3 + recent_avg * 0.2)
    return _round1(raw)


def _behavioral_score(video_rows) -> float:
    if not video_rows:
        return 0.0
    total_chunks = len(video_rows)
    risky = 0
    durations = []
    for row in video_rows:
        name = (row.platform or row.source_package or "").strip().lower()
        if any(app in name for app in HIGH_RISK_APPS):
            risky += 1
        dur = int(row.duration_seconds or 0)
        if dur > 0:
            durations.append(dur)
    risky_ratio = risky / total_chunks
    if durations:
        avg_session_duration = sum(durations) / len(durations)
    else:
        avg_session_duration = 0.0
    duration_score = _clamp(avg_session_duration / 3600.0, 0.0, 1.0)
    return _round1((risky_ratio * 0.6 + duration_score * 0.4) * 100.0)


def _scores_for_facial_qs(facial_qs):
    from face_detection.models import FacialExpressionCapture

    rows = list(facial_qs)
    completed = [r for r in rows if r.status == FacialExpressionCapture.STATUS_COMPLETED]
    return completed if completed else rows


def compute_mental_health_scores(user) -> dict:
    from face_detection.models import FacialExpressionCapture
    from users.models import VideoChunkAnalysis

    facial_qs = (
        FacialExpressionCapture.objects.filter(user=user)
        .order_by("-created_at")[:50]
    )
    facial_rows = _scores_for_facial_qs(facial_qs)
    expression_count = _completed_expression_count(user)

    video_rows = list(
        VideoChunkAnalysis.objects.filter(user=user).order_by("-created_at")[:100]
    )

    has_data = expression_count >= MIN_EXPRESSIONS_REQUIRED
    if not has_data:
        return {
            "has_data": False,
            "expression_count": expression_count,
            "min_expressions_required": MIN_EXPRESSIONS_REQUIRED,
            "stress": {"score": 0.0, "trend": "flat"},
            "anxiety": {"score": 0.0, "trend": "flat"},
            "depression": {"score": 0.0, "trend": "flat"},
            "overall": {"score": 0.0, "level": "Normal", "color": "#43A047"},
            "last_updated": None,
            "behavioral_score": 0.0,
        }

    behavioral = _behavioral_score(video_rows)

    facial_stress = _facial_emotion_score(facial_rows, "stress", "stress_score")
    facial_anxiety = _facial_emotion_score(facial_rows, "anxiety", "anxiety_score")
    facial_depression = _facial_emotion_score(facial_rows, "depression", "depression_score")

    final_stress = _round1(facial_stress * 0.6 + behavioral * 0.4)
    final_anxiety = _round1(facial_anxiety * 0.6 + behavioral * 0.4)
    final_depression = _round1(facial_depression * 0.6 + behavioral * 0.4)

    overall = _round1((final_stress + final_anxiety + final_depression) / 3.0)
    level, color = _overall_level(overall)

    last_updated = None
    if facial_rows:
        last_updated = facial_rows[0].created_at
    elif video_rows:
        last_updated = video_rows[0].created_at

    # 7-day baseline for trends (same formula, older window).
    week_ago = timezone.now() - timedelta(days=7)
    facial_week = [r for r in facial_rows if r.created_at and r.created_at >= week_ago]
    video_week = [r for r in video_rows if r.created_at and r.created_at >= week_ago]
    b_behavioral = _behavioral_score(video_week) if video_week else behavioral
    week_stress = _round1(
        _facial_emotion_score(facial_week, "stress", "stress_score") * 0.6 + b_behavioral * 0.4
    ) if facial_week else final_stress
    week_anxiety = _round1(
        _facial_emotion_score(facial_week, "anxiety", "anxiety_score") * 0.6 + b_behavioral * 0.4
    ) if facial_week else final_anxiety
    week_depression = _round1(
        _facial_emotion_score(facial_week, "depression", "depression_score") * 0.6 + b_behavioral * 0.4
    ) if facial_week else final_depression

    result = {
        "has_data": True,
        "expression_count": expression_count,
        "min_expressions_required": MIN_EXPRESSIONS_REQUIRED,
        "stress": {"score": final_stress, "trend": _trend(final_stress, week_stress)},
        "anxiety": {"score": final_anxiety, "trend": _trend(final_anxiety, week_anxiety)},
        "depression": {"score": final_depression, "trend": _trend(final_depression, week_depression)},
        "overall": {"score": overall, "level": level, "color": color},
        "last_updated": last_updated.isoformat() if last_updated else None,
        "behavioral_score": behavioral,
    }

    logger.info(
        "Mental health score computed for user:%s stress:%s anxiety:%s depression:%s",
        user.id,
        final_stress,
        final_anxiety,
        final_depression,
    )
    return result
