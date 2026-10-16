"""
Facial emotion inference — custom ResNet18 ensemble (see adult_emotion_inference.py).

ResNet18 + EfficientNet-B0 + MobileNetV3-Large ensemble (no Hugging Face / DeepFace for mood).
"""

from __future__ import annotations

from typing import Any

from .adult_emotion_inference import predict_image_pil as _predict_pil_list
from .adult_emotion_inference import predict_video_path as _predict_video


def get_classifier():
    """Legacy hook — returns the adult emotion predictor wrapper."""
    from .adult_emotion_inference import get_adult_emotion_predictor

    return get_adult_emotion_predictor()


def predict_image_pil(image) -> list[dict[str, Any]]:
    return _predict_pil_list(image)


def predict_video_path(
    video_path: str,
    max_frames: int | None = None,
    sample_fps: float | None = None,
) -> dict[str, Any]:
    return _predict_video(video_path, max_frames=max_frames, sample_fps=sample_fps)
