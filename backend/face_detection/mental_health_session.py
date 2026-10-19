"""Persist background mood + S/A/D on daily session and mental-health rows."""

from __future__ import annotations

from django.utils import timezone

from face_detection.models import MentalHealthResult


def update_daily_session_metrics(
    user,
    *,
    mood_label: str,
    emotion: str,
    stress: int,
    depression: int,
) -> None:
    from tracking.models import ScreenTimeSession

    label = (mood_label or "Neutral").strip()[:64]
    today = timezone.localdate()
    session, _ = ScreenTimeSession.objects.get_or_create(
        user=user,
        date=today,
        defaults={"total_ms": 0},
    )
    emo = (emotion or label or "").strip()[:64]
    session.mood = label
    session.emotion = emo
    session.stress_score = int(stress)
    session.depression_score = int(depression)
    session.save(
        update_fields=[
            "mood",
            "emotion",
            "stress_score",
            "depression_score",
            "updated_at",
        ]
    )


def persist_background_emotion_session(
    user,
    *,
    mood_label: str,
    emotion: str = "",
    stress: int,
    depression: int,
    source: str = "verify_track",
    probabilities: dict | None = None,
) -> None:
    label = (mood_label or "Neutral").strip()[:64]
    emo = (emotion or label).strip()[:64]

    MentalHealthResult.objects.create(
        user=user,
        stress_score=int(stress),
        anxiety_score=0,
        depression_score=int(depression),
        dominant_state=label.lower().replace(" ", "_")[:20],
        mood=label,
        source_type=_map_source(source),
        scan_type=MentalHealthResult.SCAN_UPLOADED,
        openface_summary={"emotion_probabilities": probabilities or {}},
    )

    update_daily_session_metrics(
        user,
        mood_label=label,
        emotion=emo,
        stress=stress,
        depression=depression,
    )


def _map_source(source: str) -> str:
    s = (source or "").strip().lower()
    if s in {"unlock", "verify_track", "background", "unlock_verify"}:
        return MentalHealthResult.SOURCE_UNLOCK
    if s == "screen_on":
        return MentalHealthResult.SOURCE_SCREEN_ON
    return MentalHealthResult.SOURCE_RANDOM_USAGE
