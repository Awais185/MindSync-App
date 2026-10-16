"""Manual UI + shared helpers: emotion (frames) + depression (OpenFace CSV)."""

from __future__ import annotations

import logging
import os
import tempfile
from typing import Any

logger = logging.getLogger(__name__)


def _image_bytes_to_temp_video(image_bytes: bytes, *, seconds: float = 2.0) -> str:
    import cv2
    import numpy as np

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Could not decode image for OpenFace.")
    h, w = frame.shape[:2]
    fps = 5.0
    n_frames = max(2, int(seconds * fps))
    fd, path = tempfile.mkstemp(suffix=".mp4")
    os.close(fd)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(path, fourcc, fps, (w, h))
    if not writer.isOpened():
        raise RuntimeError("Could not create temp video for OpenFace.")
    try:
        for _ in range(n_frames):
            writer.write(frame)
    finally:
        writer.release()
    return path


def _depression_from_video_path(video_path: str) -> dict[str, Any]:
    from .openface_pipeline import is_openface_available, run_openface_and_analyze

    if not is_openface_available():
        return {
            "error": "openface_unavailable",
            "message": "Depression model requires OpenFace CSV features on this server.",
        }
    analysis = run_openface_and_analyze(
        input_video_path=video_path,
        max_peak_frames=0,
        include_tracked_video=False,
        fast_mode=True,
        max_video_seconds=35.0,
        use_depression_model=True,
    )
    scores = dict(analysis.scores or {})
    dm = scores.get("depression_model") or {}
    return {
        "predicted_label": dm.get("predicted_label"),
        "predicted_class_id": dm.get("predicted_class_id"),
        "average_class_probabilities_percent": dm.get(
            "average_class_probabilities_percent"
        ),
        "stress_score": scores.get("stress_score"),
        "anxiety_score": scores.get("anxiety_score"),
        "depression_score": scores.get("depression_score"),
        "warning": dm.get("warning"),
        "valid_frames": dm.get("valid_frames"),
    }


def analyze_manual_image(image_bytes: bytes) -> dict[str, Any]:
    from .mood_scan_service import analyze_image_bytes

    mood = analyze_image_bytes(image_bytes)
    depression: dict[str, Any] = {"skipped": True, "reason": "openface_requires_video"}
    tmp = None
    try:
        tmp = _image_bytes_to_temp_video(image_bytes)
        depression = _depression_from_video_path(tmp)
    except Exception as exc:
        logger.warning("Manual image depression path failed: %s", exc)
        depression = {"error": "depression_analysis_failed", "detail": str(exc)[:300]}
    finally:
        if tmp and os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
    return {"mood": mood, "depression": depression, "mood_saved": False}


def analyze_manual_video(video_path: str) -> dict[str, Any]:
    from .adult_emotion_inference import predict_video_path as adult_emotion_video

    mood = adult_emotion_video(video_path, max_frames=4, sample_fps=0.35)
    try:
        depression = _depression_from_video_path(video_path)
    except Exception as exc:
        logger.warning("Manual video depression path failed: %s", exc)
        depression = {"error": "depression_analysis_failed", "detail": str(exc)[:300]}
    return {
        "mood": mood,
        "depression": depression,
        "mood_saved": False,
    }
