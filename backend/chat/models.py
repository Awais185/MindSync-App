from django.db import models
from django.contrib.auth.models import User


class UserMentalState(models.Model):
    """
    Snapshot of contextual wellness signals used to personalize chat responses.
    Extend later with voice / passive sensing fields without breaking the API.
    """

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='mental_state')
    stress_level = models.CharField(max_length=64, default='not recorded')
    sleep_quality = models.CharField(max_length=64, default='not recorded')
    screen_time = models.CharField(max_length=64, default='not recorded')
    emotion = models.CharField(max_length=64, default='not recorded')
    behavior = models.TextField(blank=True, default='')
    last_updated = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-last_updated']

    def __str__(self):
        return f'MentalState<{self.user.username}>'


class ChatMessage(models.Model):
    """One row per turn: user text + model reply (audit trail for context)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='chat_messages')
    session = models.ForeignKey(
        'ChatSession',
        on_delete=models.CASCADE,
        related_name='messages',
        null=True,
        blank=True,
    )
    message = models.TextField()
    response = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'Chat<{self.user.username} @ {self.created_at}>'


class ChatSession(models.Model):
    """Conversation container so clients can create and load previous chats."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='chat_sessions')
    title = models.CharField(max_length=120, default='New chat')
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)

    class Meta:
        ordering = ['-updated_at']

    def __str__(self):
        return f'Session<{self.user.username} {self.id}>'


# =============================================================================
# Facial emotion ML (singleton) — weights under chat/weights/
# - image_model.pth / video_model.pth: optional TorchScript
# - hf_emotion/: Hugging Face snapshot (see download_chat_weights.py)
# =============================================================================
import json
import logging
import os
import threading
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_ML_LOCK = threading.Lock()
_HF_PIPELINE: Any = None
_JIT_IMAGE: Any = None
_JIT_VIDEO: Any = None
_LABELS_IMAGE: list[str] | None = None
_LABELS_VIDEO: list[str] | None = None


def _weights_base() -> Path:
    from django.conf import settings

    return Path(getattr(settings, "CHAT_WEIGHTS_DIR", Path(__file__).resolve().parent / "weights"))


def _hf_local_dir() -> Path:
    from django.conf import settings

    sub = getattr(settings, "CHAT_EMOTION_HF_SUBDIR", "hf_emotion")
    return _weights_base() / sub


def _hf_model_id() -> str:
    from django.conf import settings

    return getattr(settings, "CHAT_EMOTION_MODEL_ID", "dima806/facial_emotions_image_detection")


def _read_labels_file(name: str) -> list[str]:
    p = _weights_base() / name
    if not p.is_file():
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return [str(x) for x in data]
    except (OSError, json.JSONDecodeError):
        pass
    return []


def _load_jit(path: Path, map_location: str | None = None):
    import torch

    loc = map_location or ("cuda" if torch.cuda.is_available() else "cpu")
    m = torch.jit.load(str(path), map_location=loc)
    m.eval()
    return m


def _jit_preprocess(pil_image):
    import torch
    from torchvision import transforms

    t = transforms.Compose(
        [
            transforms.Resize(256),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ]
    )
    return t(pil_image.convert("RGB")).unsqueeze(0)


def _predict_jit(model, pil_image, labels: list[str]) -> tuple[str, float]:
    import torch

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    x = _jit_preprocess(pil_image).to(device)
    model = model.to(device)
    with torch.no_grad():
        out = model(x)
        if out.dim() == 1:
            out = out.unsqueeze(0)
        probs = torch.softmax(out, dim=1)[0]
        conf, idx = probs.max(dim=0)
    i = int(idx.cpu())
    label = labels[i] if labels and i < len(labels) else f"class_{i}"
    return label, float(conf.cpu())


def _emotion_pipeline_kwargs(model_src: str) -> dict[str, Any]:
    """Build kwargs so local folders do not hit the Hub; hub ids stay online."""
    device_env = os.environ.get("EMOTION_DEVICE", "").strip()
    kwargs: dict[str, Any] = {"model": model_src, "trust_remote_code": True}
    if device_env:
        kwargs["device"] = int(device_env) if device_env.isdigit() else device_env
    # local_files_only is for from_pretrained only — not supported on pipeline() in newer transformers.
    return kwargs


def _get_hf_pipeline():
    global _HF_PIPELINE
    with _ML_LOCK:
        if _HF_PIPELINE is None:
            from face_detection.hf_emotion_loader import load_image_classifier_with_fallback

            local = _hf_local_dir()
            hub_id = _hf_model_id()
            if local.is_dir() and (local / "config.json").is_file():
                src = str(local.resolve())
            else:
                src = hub_id
            logger.info("Loading HF emotion classifier from: %s", src)
            device_env = os.environ.get("EMOTION_DEVICE", "").strip()
            try:
                _HF_PIPELINE = load_image_classifier_with_fallback(
                    src,
                    hub_id,
                    device_env=device_env,
                )
            except Exception:
                logger.exception("HF emotion classifier failed for %s; retrying hub id %s", src, hub_id)
                _HF_PIPELINE = load_image_classifier_with_fallback(
                    hub_id,
                    hub_id,
                    device_env=device_env,
                )
        return _HF_PIPELINE


def _get_jit_image():
    global _JIT_IMAGE, _LABELS_IMAGE
    if _JIT_IMAGE is not None or getattr(_get_jit_image, "_tried", False):
        return _JIT_IMAGE, (_LABELS_IMAGE or [])
    with _ML_LOCK:
        if getattr(_get_jit_image, "_tried", False):
            return _JIT_IMAGE, (_LABELS_IMAGE or [])
        _get_jit_image._tried = True  # type: ignore[attr-defined]
        p = _weights_base() / "image_model.pth"
        if p.is_file():
            try:
                _JIT_IMAGE = _load_jit(p)
                _LABELS_IMAGE = _read_labels_file("image_labels.json")
                logger.info("Loaded TorchScript image model: %s", p)
            except Exception:
                logger.exception("Failed to load image_model.pth; falling back to HF.")
                _JIT_IMAGE = None
                _LABELS_IMAGE = []
        return _JIT_IMAGE, (_LABELS_IMAGE or [])


def _get_jit_video():
    global _JIT_VIDEO, _LABELS_VIDEO
    if _JIT_VIDEO is not None or getattr(_get_jit_video, "_tried", False):
        return _JIT_VIDEO, (_LABELS_VIDEO or [])
    with _ML_LOCK:
        if getattr(_get_jit_video, "_tried", False):
            return _JIT_VIDEO, (_LABELS_VIDEO or [])
        _get_jit_video._tried = True  # type: ignore[attr-defined]
        p = _weights_base() / "video_model.pth"
        if p.is_file():
            try:
                _JIT_VIDEO = _load_jit(p)
                _LABELS_VIDEO = _read_labels_file("video_labels.json") or _read_labels_file(
                    "image_labels.json"
                )
                logger.info("Loaded TorchScript video model: %s", p)
            except Exception:
                logger.exception("Failed to load video_model.pth; using image/HF path for video.")
                _JIT_VIDEO = None
                _LABELS_VIDEO = []
        return _JIT_VIDEO, (_LABELS_VIDEO or [])


def predict_emotion_pil_image(pil_image, *, for_video: bool = False) -> tuple[str, float]:
    """
    Single-frame prediction. Used by image API and by video_model frame loop.
    Priority for video: video_model.pth > image_model.pth > HF pipeline.
    Priority for image: image_model.pth > HF pipeline.
    """
    from PIL import Image

    if not isinstance(pil_image, Image.Image):
        raise TypeError("Expected PIL.Image")

    if for_video:
        jv, lv = _get_jit_video()
        if jv is not None:
            return _predict_jit(jv, pil_image, lv)
        ji, li = _get_jit_image()
        if ji is not None:
            return _predict_jit(ji, pil_image, li)

    else:
        ji, li = _get_jit_image()
        if ji is not None:
            return _predict_jit(ji, pil_image, li)

    return _hf_classify_pil_image(pil_image)


def _hf_classify_pil_image(pil_image) -> tuple[str, float]:
    """Direct model inference via shared HF loader (no transformers.pipeline import)."""
    clf = _get_hf_pipeline()
    raw = clf(pil_image)
    if not raw:
        return "unknown", 0.0
    top = raw[0]
    return str(top["label"]), float(top["score"])


def analyze_uploaded_image_file(uploaded_file) -> tuple[str, float]:
    """Django UploadedFile -> (prediction label, confidence 0..1)."""
    from PIL import Image

    try:
        uploaded_file.seek(0)
    except (AttributeError, OSError):
        pass
    with Image.open(uploaded_file) as img:
        img = img.convert("RGB")
        return predict_emotion_pil_image(img, for_video=False)
