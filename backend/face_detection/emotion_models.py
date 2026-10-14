"""
Local facial emotion inference for API use.
Loads dima806/facial_emotions_image_detection from ./weights/facial_emotions when present,
otherwise from Hugging Face Hub (first run caches to HF cache).
"""
from __future__ import annotations

import logging
import os
import threading
from collections import Counter
from pathlib import Path
from typing import Any

from django.conf import settings

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_classifier = None

DEFAULT_MODEL_ID = "dima806/facial_emotions_image_detection"


def _weights_dir() -> Path:
    base = getattr(settings, "EMOTION_WEIGHTS_DIR", None)
    if base:
        return Path(base)
    return Path(__file__).resolve().parent / "weights" / "facial_emotions"


def _model_source() -> str:
    """Local folder if it contains model files; else HF model id."""
    d = _weights_dir()
    if d.is_dir():
        for name in ("config.json", "preprocessor_config.json"):
            if (d / name).is_file():
                return str(d)
    return getattr(settings, "EMOTION_MODEL_ID", DEFAULT_MODEL_ID)


def get_classifier():
    """Thread-safe lazy load of the image-classification model."""
    global _classifier
    with _lock:
        if _classifier is None:
            from .hf_emotion_loader import load_image_classifier_with_fallback

            src = _model_source()
            logger.info("Loading emotion classifier from: %s", src)
            device_env = os.environ.get("EMOTION_DEVICE", "").strip()
            _classifier = load_image_classifier_with_fallback(
                src,
                DEFAULT_MODEL_ID,
                device_env=device_env,
            )
            logger.info("Emotion classifier ready.")
        return _classifier


def predict_image_pil(image) -> list[dict[str, Any]]:
    """Run classifier on a PIL Image; return list of {label, score}."""
    clf = get_classifier()
    raw = clf(image)
    if not raw:
        return []
    return [{"label": str(x["label"]), "score": float(x["score"])} for x in raw]


def predict_video_path(
    video_path: str,
    max_frames: int | None = None,
    sample_fps: float | None = None,
) -> dict[str, Any]:
    """
    Sample frames from a video file (same logic as standalone video.py, JSON-friendly).
    sample_fps: if set, take about this many frames per second (default: 1 FPS).
    max_frames: hard cap on number of frames analyzed.
    """
    import cv2

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {"error": "Could not open video", "frames": [], "summary": {}, "dominant": None}

    frame_rate = cap.get(cv2.CAP_PROP_FPS) or 25.0
    frame_rate = max(frame_rate, 1.0)
    interval = int(frame_rate) if sample_fps is None else max(int(frame_rate / sample_fps), 1)

    clf = get_classifier()
    predictions: list[dict[str, Any]] = []
    frame_num = 0

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_num % interval == 0:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                from PIL import Image

                pil_image = Image.fromarray(rgb)
                result = clf(pil_image)
                if result:
                    top = result[0]
                    predictions.append(
                        {
                            "frame_num": frame_num,
                            "time_sec": round(frame_num / frame_rate, 3),
                            "label": str(top["label"]),
                            "confidence": float(top["score"]),
                            "top_k": [
                                {"label": str(x["label"]), "score": float(x["score"])}
                                for x in result[:5]
                            ],
                        }
                    )
                if max_frames is not None and len(predictions) >= max_frames:
                    break
            frame_num += 1
    finally:
        cap.release()

    if not predictions:
        return {
            "frames": [],
            "summary": {},
            "dominant": None,
            "frame_count": 0,
            "fps": frame_rate,
        }

    labels = [p["label"] for p in predictions]
    counts = Counter(labels)
    dominant = counts.most_common(1)[0][0]

    return {
        "frames": predictions,
        "summary": dict(counts),
        "dominant": dominant,
        "frame_count": len(predictions),
        "fps": frame_rate,
        "sample_interval_frames": interval,
    }
