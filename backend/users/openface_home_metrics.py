"""Home UI: 3-day emotional resilience + OpenFace capture aggregates."""

from __future__ import annotations

from collections import Counter
from datetime import datetime, time, timedelta
from typing import Any

from django.utils import timezone

_WEEKDAY_SHORT = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

_EMOTION_DISPLAY = {
    "happy": "Happy",
    "happiness": "Happy",
    "joy": "Happy",
    "neutral": "Neutral",
    "calm": "Neutral",
    "stress": "Stress",
    "stressed": "Stress",
    "anxiety": "Stress",
    "anxious": "Stress",
    "depression": "Low",
    "depressed": "Low",
    "sad": "Sad",
    "sadness": "Sad",
    "unhappy": "Unhappy",
    "fear": "Stress",
    "angry": "Stress",
}


def _day_bounds(d):
    start_dt = timezone.make_aware(datetime.combine(d, time.min))
    end_dt = start_dt + timedelta(days=1)
    return start_dt, end_dt


def _display_emotion(raw: str) -> str:
    key = (raw or "").strip().lower()
    if not key:
        return "Neutral"
    if key in _EMOTION_DISPLAY:
        return _EMOTION_DISPLAY[key]
    for token, label in _EMOTION_DISPLAY.items():
        if token in key:
            return label
    return raw.strip().title()


def _label_from_capture(row) -> str:
    """Use raw emotion-model labels (Happy, Sad, Fear, …) — never severity buckets like Low."""
    stored = (getattr(row, "emotion", None) or "").strip()
    if stored:
        return stored.strip().title()
    mood = row.mood if isinstance(row.mood, dict) else {}
    for key in ("prediction", "class", "dominant"):
        raw = mood.get(key)
        if raw:
            return str(raw).strip().title()
    au = row.au_results if isinstance(row.au_results, dict) else {}
    emo = au.get("emotion_label")
    if emo:
        return str(emo).strip().title()
    raw = (row.dominant_state or "").strip()
    if raw and raw.lower() not in {"neutral", "unknown", ""}:
        return raw.replace("_", " ").title()
    return "Awaiting scan"


def _bar_color_key(emotion_label: str) -> str:
    low = emotion_label.lower()
    if "awaiting" in low:
        return "neutral"
    if any(t in low for t in ("happy", "joy", "calm", "neutral")):
        return "positive"
    if any(t in low for t in ("fear", "angry", "anger", "disgust", "stress", "anxious")):
        return "stress"
    if any(t in low for t in ("sad", "unhappy", "depress", "fearful")):
        return "low"
    return "neutral"


def openface_capture_averages(user, *, window_days: int) -> dict[str, Any] | None:
    from face_detection.models import FacialExpressionCapture

    window_days = max(1, min(int(window_days), 30))
    cutoff = timezone.now() - timedelta(days=window_days)
    rows = list(
        FacialExpressionCapture.objects.filter(
            user=user,
            status=FacialExpressionCapture.STATUS_COMPLETED,
            created_at__gte=cutoff,
        ).order_by("-created_at")[:80]
    )
    if not rows:
        return None
    n = float(len(rows))
    return {
        "capture_count": len(rows),
        "stress": round(sum(r.stress_score for r in rows) / n, 1),
        "depression": round(sum(r.depression_score for r in rows) / n, 1),
    }


def _emotion_from_mood_json(mood) -> str:
    if not isinstance(mood, dict):
        return ""
    return str(mood.get("prediction") or mood.get("class") or "").strip()


def latest_predicted_emotion(user) -> str:
    """Most recent emotion label from unlock mood scans or background expression video."""
    from face_detection.models import FaceMoodScan, FacialExpressionCapture

    cap = (
        FacialExpressionCapture.objects.filter(
            user=user,
            status=FacialExpressionCapture.STATUS_COMPLETED,
        )
        .order_by("-processed_at", "-created_at")
        .first()
    )
    scan = (
        FaceMoodScan.objects.filter(user=user, matched=True)
        .order_by("-created_at")
        .first()
    )

    cap_at = None
    if cap:
        cap_at = getattr(cap, "processed_at", None) or cap.created_at
    scan_at = scan.created_at if scan else None

    if scan_at and (cap_at is None or scan_at >= cap_at):
        label = _emotion_from_mood_json(getattr(scan, "mood", None))
        if label:
            return label.replace("_", " ").strip().title()

    if cap:
        label = (getattr(cap, "emotion", None) or "").strip()
        if not label:
            label = _emotion_from_mood_json(cap.mood)
        if label:
            return label.replace("_", " ").strip().title()

    return ""


def build_emotional_resilience_window(user, *, days: int = 3) -> list[dict[str, Any]]:
    """Rolling calendar days (oldest → newest) from background OpenFace captures."""
    from face_detection.models import FacialExpressionCapture

    days = max(1, min(int(days), 7))
    today = timezone.localdate()
    out: list[dict[str, Any]] = []
    for i in range(days - 1, -1, -1):
        d = today - timedelta(days=i)
        start_dt, end_dt = _day_bounds(d)
        rows = list(
            FacialExpressionCapture.objects.filter(
                user=user,
                status=FacialExpressionCapture.STATUS_COMPLETED,
                created_at__gte=start_dt,
                created_at__lt=end_dt,
            )
        )
        if rows:
            labels = [
                _label_from_capture(r)
                for r in rows
                if (r.emotion or "").strip()
                or _emotion_from_mood_json(r.mood)
            ]
            if not labels:
                labels = [_label_from_capture(r) for r in rows]
            emotion_label = Counter(labels).most_common(1)[0][0]
            stress = sum(r.stress_score for r in rows) / len(rows)
            dep = sum(r.depression_score for r in rows) / len(rows)
            fill = max(0.0, min(1.0, (100.0 - (stress + dep) / 2.0) / 100.0))
        else:
            emotion_label = "Awaiting scan"
            fill = 0.0
        out.append(
            {
                "date": d.isoformat(),
                "day_name": _WEEKDAY_SHORT[d.weekday()],
                "emotion_label": emotion_label,
                "resilience_fill": round(fill, 3),
                "samples": len(rows),
                "tone": _bar_color_key(emotion_label),
            }
        )
    return out
