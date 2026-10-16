"""Preload Deep Face Analysis models (emotion + MediaPipe mesh; OpenFace when on Windows)."""

from __future__ import annotations

import logging
import threading

logger = logging.getLogger(__name__)

_warm_lock = threading.Lock()
_warmed = False


def ensure_behavior_models_warm() -> dict[str, bool]:
    """Load models once per process; safe to call from warmup endpoint and analyze."""
    global _warmed
    with _warm_lock:
        if _warmed:
            return status_behavior_models()
        status = _load_all()
        _warmed = bool(
            status.get("mediapipe_or_openface") or status.get("emotion")
        )
        return status


def status_behavior_models() -> dict[str, bool]:
    from .openface_pipeline import is_openface_available

    emotion = False
    mediapipe = False
    try:
        from .adult_emotion_inference import get_adult_emotion_predictor

        get_adult_emotion_predictor()
        emotion = True
    except Exception:
        pass
    try:
        from .face_mesh_au import mediapipe_available, warmup_face_mesh

        if mediapipe_available():
            mediapipe = warmup_face_mesh()
    except Exception:
        pass
    openface = is_openface_available()
    return {
        "emotion": emotion,
        "mediapipe": mediapipe,
        "openface": openface,
        "mediapipe_or_openface": mediapipe or openface,
    }


def _load_all() -> dict[str, bool]:
    status = status_behavior_models()
    logger.info(
        "behavior analysis warmup emotion=%s mediapipe=%s openface=%s",
        status["emotion"],
        status["mediapipe"],
        status["openface"],
    )
    return status
