"""
Video analysis: sample frames, run the same singleton emotion backend as images.
Loads optional TorchScript `video_model.pth` via chat.models (per-frame); otherwise HF / image_model.pth.
"""
from __future__ import annotations

import logging
from collections import Counter
from typing import Any

logger = logging.getLogger(__name__)


def analyze_video_file_path(video_path: str, max_frames: int | None = None) -> dict[str, Any]:
    """
    Returns unified API keys: prediction (dominant label), confidence (0..1),
    plus optional diagnostics for debugging.
    """
    import cv2
    from django.conf import settings
    from PIL import Image

    from chat.models import predict_emotion_pil_image

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError("Could not open video file")

    frame_rate = float(cap.get(cv2.CAP_PROP_FPS) or 25.0)
    frame_rate = max(frame_rate, 1.0)
    interval = int(frame_rate)

    limit = max_frames
    if limit is None:
        limit = int(getattr(settings, "CHAT_VIDEO_MAX_FRAMES", 120))

    labels: list[str] = []
    confidences: list[float] = []
    frame_num = 0
    sampled = 0

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_num % interval == 0:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                pil_image = Image.fromarray(rgb)
                label, conf = predict_emotion_pil_image(pil_image, for_video=True)
                labels.append(label)
                confidences.append(conf)
                sampled += 1
                if sampled >= limit:
                    break
            frame_num += 1
    finally:
        cap.release()

    if not labels:
        return {
            "prediction": "unknown",
            "confidence": 0.0,
            "frames_sampled": 0,
            "summary": {},
        }

    counts = Counter(labels)
    dominant, vote_count = counts.most_common(1)[0]
    agreement = vote_count / len(labels)
    mean_conf = sum(c for l, c in zip(labels, confidences) if l == dominant) / max(
        vote_count, 1
    )
    confidence = float(min(1.0, max(agreement, mean_conf)))

    return {
        "prediction": dominant,
        "confidence": round(confidence, 4),
        "frames_sampled": len(labels),
        "summary": dict(counts),
    }
