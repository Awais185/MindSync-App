"""Load Hugging Face image-classification without brittle `from transformers import pipeline`."""

from __future__ import annotations

import importlib
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


class HfImageClassifier:
    """Minimal pipeline-compatible wrapper for image-classification."""

    def __init__(self, model: Any, image_processor: Any, device: Any) -> None:
        self.model = model
        self.image_processor = image_processor
        self.device = device

    def __call__(self, pil_image: Any) -> list[dict[str, Any]]:
        import torch

        inputs = self.image_processor(images=pil_image, return_tensors="pt")
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        with torch.no_grad():
            logits = self.model(**inputs).logits
        probs = torch.nn.functional.softmax(logits[0], dim=-1)
        id2label = getattr(self.model.config, "id2label", None) or {}
        rows: list[dict[str, Any]] = []
        for idx, score in enumerate(probs.tolist()):
            label = id2label.get(idx, f"class_{idx}")
            rows.append({"label": str(label), "score": float(score)})
        rows.sort(key=lambda x: x["score"], reverse=True)
        return rows


def _resolve_device(device_env: str) -> Any:
    if not device_env:
        return "cpu"
    if device_env.isdigit():
        return int(device_env)
    return device_env


def load_image_classifier(model_src: str, *, device_env: str = "") -> HfImageClassifier:
    """
    Prefer AutoModel + processor (works on transformers 4.x and 5.x).
    Falls back to pipeline() only if direct load fails.
    """
    device = _resolve_device(device_env or os.environ.get("EMOTION_DEVICE", "").strip())

    try:
        auto_model = importlib.import_module("transformers").AutoModelForImageClassification
        auto_processor = importlib.import_module("transformers").AutoImageProcessor
    except Exception as exc:
        raise ImportError(
            "transformers is not installed correctly. "
            "Run: pip install 'transformers>=4.36.0' torch torchvision"
        ) from exc

    import torch

    processor = auto_processor.from_pretrained(model_src, trust_remote_code=True)
    model = auto_model.from_pretrained(model_src, trust_remote_code=True)
    model.eval()
    if device != "cpu":
        model.to(device)
    logger.info("Loaded HF image classifier (direct) from: %s device=%s", model_src, device)
    return HfImageClassifier(model, processor, device)


def load_image_classifier_with_fallback(
    primary_src: str,
    fallback_src: str,
    *,
    device_env: str = "",
) -> HfImageClassifier:
    try:
        return load_image_classifier(primary_src, device_env=device_env)
    except Exception as exc:
        if primary_src != fallback_src:
            logger.warning(
                "HF classifier failed for %s (%s); trying %s",
                primary_src,
                exc,
                fallback_src,
            )
            return load_image_classifier(fallback_src, device_env=device_env)
        logger.exception("HF classifier failed for %s", primary_src)
        raise
