"""
Adult emotion / mood — 3-architecture ensemble (ResNet18, EfficientNet-B0, MobileNetV3-Large).

Each architecture uses 5-fold weights (best_{arch}_fold{0..4}.pt).
Per-architecture: average fold softmax probabilities.
Final label: average of the 3 architecture probability vectors (soft vote),
with per-architecture top-class votes exposed in the response.
"""

from __future__ import annotations

import io
import json
import logging
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from django.conf import settings
from PIL import Image

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_predictor: "AdultEmotionPredictor | None" = None

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)

DEFAULT_ENSEMBLE_MODELS = ("resnet18", "efficientnet_b0", "mobilenetv3_large")

ARCHITECTURE_DISPLAY_NAMES: dict[str, str] = {
    "resnet18": "ResNet18",
    "efficientnet_b0": "EfficientNet",
    "mobilenetv3_large": "MobileNet",
}


def _model_predictions_payload(
    architecture_votes: dict[str, str],
    architecture_confidences: dict[str, float],
) -> list[dict[str, Any]]:
    order = DEFAULT_ENSEMBLE_MODELS
    rows: list[dict[str, Any]] = []
    for arch in order:
        if arch not in architecture_votes:
            continue
        from .json_safe import finite_float

        conf = finite_float(architecture_confidences.get(arch), 0.0)
        rows.append(
            {
                "model": ARCHITECTURE_DISPLAY_NAMES.get(arch, arch),
                "architecture": arch,
                "label": architecture_votes[arch],
                "confidence": round(conf, 4),
            }
        )
    return rows

_EMOTION_MH_SCORES: dict[str, tuple[int, int, int]] = {
    "anger": (82, 72, 42),
    "contempt": (70, 58, 40),
    "disgust": (68, 55, 45),
    "fear": (78, 88, 52),
    "happiness": (22, 18, 14),
    "sadness": (48, 55, 82),
    "surprise": (42, 48, 32),
    "neutral": (40, 40, 38),
}


@dataclass(frozen=True)
class EmotionModelConfig:
    img_size: int
    num_classes: int
    n_folds: int
    class_display: tuple[str, ...]
    ensemble_models: tuple[str, ...]

    @classmethod
    def load(cls, model_dir: Path) -> "EmotionModelConfig":
        cfg_path = model_dir / "emotion_config.json"
        classes = (
            "Anger",
            "Contempt",
            "Disgust",
            "Fear",
            "Happiness",
            "Sadness",
            "Surprise",
        )
        ensemble = DEFAULT_ENSEMBLE_MODELS
        img_size = 224
        n_folds = 5
        num_classes = 7
        if cfg_path.is_file():
            data = json.loads(cfg_path.read_text(encoding="utf-8"))
            if data.get("class_display"):
                classes = tuple(str(c) for c in data["class_display"])
            raw_ens = data.get("ensemble_models")
            if isinstance(raw_ens, list) and raw_ens:
                ensemble = tuple(str(m) for m in raw_ens)
            elif data.get("model_name"):
                ensemble = (str(data["model_name"]),)
            img_size = int(data.get("img_size") or img_size)
            n_folds = int(data.get("n_folds") or n_folds)
            num_classes = int(data.get("num_classes") or len(classes))
        return cls(
            img_size=img_size,
            num_classes=num_classes,
            n_folds=n_folds,
            class_display=classes,
            ensemble_models=ensemble,
        )


def adult_emotion_model_dir() -> Path:
    raw = getattr(settings, "ADULT_EMOTION_MODEL_DIR", None)
    if raw:
        return Path(raw).expanduser().resolve()
    return (
        Path(settings.BASE_DIR) / "models" / "Adult Emotion Detection Model"
    ).resolve()


def mental_health_scores_from_emotion(label: str) -> tuple[int, int, int]:
    key = (label or "").strip().lower()
    return _EMOTION_MH_SCORES.get(key, _EMOTION_MH_SCORES["neutral"])


def _timm_model_name(model_name: str) -> str:
    name = model_name.strip().lower()
    if name in {"mobilenetv3_large", "mobilenet_v3_large"}:
        return "mobilenetv3_large_100"
    return name


def build_model(model_name: str, num_classes: int, pretrained: bool = False):
    import torch.nn as nn

    name = model_name.strip().lower()
    if name == "resnet18":
        from torchvision.models import ResNet18_Weights, resnet18

        weights = ResNet18_Weights.DEFAULT if pretrained else None
        model = resnet18(weights=weights)
        model.fc = nn.Linear(model.fc.in_features, num_classes)
        return model
    if name in {"efficientnet_b0", "mobilenetv3_large", "mobilenet_v3_large"}:
        import timm

        timm_name = _timm_model_name(name)
        return timm.create_model(
            timm_name,
            pretrained=pretrained,
            num_classes=num_classes,
        )
    raise ValueError(f"Unsupported emotion architecture: {model_name}")


def _torch_load(path: Path, device):
    import torch

    try:
        return torch.load(path, map_location=device, weights_only=False)
    except TypeError:
        return torch.load(path, map_location=device)


def discover_weight_files(model_dir: Path, arch: str, n_folds: int) -> list[Path]:
    """Return existing fold checkpoints for an architecture (sorted by fold)."""
    found: list[Path] = []
    for fold in range(n_folds):
        p = model_dir / f"best_{arch}_fold{fold}.pt"
        if p.is_file():
            found.append(p)
    return found


class AdultEmotionPredictor:
    def __init__(self, cfg: EmotionModelConfig, output_dir: Path, device):
        import torch
        from torchvision import transforms

        self.cfg = cfg
        self.output_dir = output_dir
        self.device = device
        self.transform = transforms.Compose(
            [
                transforms.Grayscale(num_output_channels=3),
                transforms.Resize((cfg.img_size, cfg.img_size)),
                transforms.ToTensor(),
                transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
            ]
        )
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        self.face_detector = cv2.CascadeClassifier(cascade_path)
        # arch_name -> list of eval models (one per fold)
        self._models_by_arch: dict[str, list[Any]] = {}
        self._load_ensemble()

    def _load_ensemble(self) -> None:
        loaded_archs: list[str] = []
        for arch in self.cfg.ensemble_models:
            paths = discover_weight_files(self.output_dir, arch, self.cfg.n_folds)
            if not paths:
                logger.warning(
                    "No weights for architecture %s in %s — skipping",
                    arch,
                    self.output_dir,
                )
                continue
            if len(paths) < self.cfg.n_folds:
                logger.warning(
                    "Architecture %s: found %s/%s fold files — using available folds",
                    arch,
                    len(paths),
                    self.cfg.n_folds,
                )
            models: list[Any] = []
            for weight_path in paths:
                model = build_model(arch, self.cfg.num_classes, pretrained=False)
                state = _torch_load(weight_path, self.device)
                model.load_state_dict(state)
                model = model.to(self.device)
                model.eval()
                models.append(model)
            self._models_by_arch[arch] = models
            loaded_archs.append(arch)
            logger.info(
                "Loaded %s (%d folds) from %s",
                arch,
                len(models),
                self.output_dir,
            )

        if not self._models_by_arch:
            raise FileNotFoundError(
                f"No emotion weights found in {self.output_dir}. "
                f"Expected best_{{arch}}_fold{{0..{self.cfg.n_folds - 1}}}.pt for "
                f"{', '.join(self.cfg.ensemble_models)}."
            )
        logger.info(
            "Adult emotion ensemble ready: %s",
            ", ".join(loaded_archs),
        )

    def crop_face_pil(self, image: Image.Image, margin: float = 0.2) -> Image.Image:
        rgb = np.array(image.convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        faces = self.face_detector.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80)
        )
        if len(faces) == 0:
            return image.convert("RGB")
        x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
        cx, cy = x + w // 2, y + h // 2
        size = int(max(w, h) * (1 + margin))
        x1 = max(0, cx - size // 2)
        y1 = max(0, cy - size // 2)
        x2 = min(bgr.shape[1], cx + size // 2)
        y2 = min(bgr.shape[0], cy + size // 2)
        crop = bgr[y1:y2, x1:x2]
        return Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))

    def _architecture_mean_probs(self, tensor) -> np.ndarray:
        import torch

        arch_vectors: list[np.ndarray] = []
        architecture_votes: dict[str, str] = {}
        architecture_confidences: dict[str, float] = {}

        for arch, models in self._models_by_arch.items():
            fold_probs: list[np.ndarray] = []
            with torch.no_grad():
                for model in models:
                    logits = model(tensor)
                    probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
                    fold_probs.append(probs)
            mean_p = np.mean(fold_probs, axis=0)
            arch_vectors.append(mean_p)
            idx = int(np.argmax(mean_p))
            label = self.cfg.class_display[idx]
            architecture_votes[arch] = label
            architecture_confidences[arch] = float(mean_p[idx])

        # Soft vote: equal-weight average of per-architecture distributions
        fused = np.mean(arch_vectors, axis=0)
        pred_idx = int(np.argmax(fused))

        # Hard vote tie-break metadata
        from collections import Counter

        vote_counts = Counter(architecture_votes.values())
        majority_label, majority_count = vote_counts.most_common(1)[0]

        return fused, pred_idx, architecture_votes, architecture_confidences, majority_label, majority_count

    def predict_pil(self, image: Image.Image) -> dict[str, Any]:
        face = self.crop_face_pil(image)
        tensor = self.transform(face.convert("L")).unsqueeze(0).to(self.device)

        fused, pred_idx, arch_votes, arch_conf, majority_label, majority_count = (
            self._architecture_mean_probs(tensor)
        )
        fused_conf = float(fused[pred_idx])
        # Final label: majority vote across the three architectures (ties → soft fusion argmax).
        final_label = majority_label
        if majority_count < 2 and len(arch_votes) >= 2:
            final_label = self.cfg.class_display[pred_idx]
        majority_conf = float(
            np.mean(
                [
                    arch_conf[a]
                    for a, lbl in arch_votes.items()
                    if lbl == final_label
                ]
            )
            if arch_votes
            else fused_conf
        )

        return {
            "class": final_label,
            "prediction": final_label,
            "confidence": round(majority_conf, 4),
            "probabilities": {
                self.cfg.class_display[i]: float(fused[i])
                for i in range(len(self.cfg.class_display))
            },
            "model": "tri_architecture_ensemble",
            "ensemble_architectures": list(self._models_by_arch.keys()),
            "architecture_votes": arch_votes,
            "architecture_confidences": arch_conf,
            "model_predictions": _model_predictions_payload(arch_votes, arch_conf),
            "majority_vote_label": final_label,
            "majority_vote_count": majority_count,
            "status": "success",
        }

    def predict_bytes(self, image_bytes: bytes) -> dict[str, Any]:
        with Image.open(io.BytesIO(image_bytes)) as img:
            return self.predict_pil(img.convert("RGB"))

    def predict_path(self, path: str | Path) -> dict[str, Any]:
        with Image.open(path) as img:
            return self.predict_pil(img.convert("RGB"))


def get_adult_emotion_predictor() -> AdultEmotionPredictor:
    global _predictor
    with _lock:
        if _predictor is None:
            import torch

            model_dir = adult_emotion_model_dir()
            cfg = EmotionModelConfig.load(model_dir)
            device = torch.device(
                "cuda"
                if torch.cuda.is_available()
                else (
                    "mps"
                    if getattr(torch.backends, "mps", None)
                    and torch.backends.mps.is_available()
                    else "cpu"
                )
            )
            logger.info(
                "Loading adult emotion ensemble from %s on %s (archs=%s)",
                model_dir,
                device,
                ",".join(cfg.ensemble_models),
            )
            _predictor = AdultEmotionPredictor(cfg, model_dir, device)
        return _predictor


def predict_image_bytes(image_bytes: bytes) -> dict[str, Any]:
    out = get_adult_emotion_predictor().predict_bytes(image_bytes)
    out["modality"] = "image"
    return out


def predict_image_pil(image: Image.Image) -> list[dict[str, Any]]:
    out = get_adult_emotion_predictor().predict_pil(image)
    label = str(out.get("class") or out.get("prediction") or "Unknown")
    conf = float(out.get("confidence") or 0.0)
    return [{"label": label, "score": conf}]


def predict_video_path(
    video_path: str,
    max_frames: int | None = 12,
    sample_fps: float | None = 1.0,
) -> dict[str, Any]:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {
            "error": "Could not open video",
            "frames": [],
            "summary": {},
            "dominant": None,
        }

    frame_rate = cap.get(cv2.CAP_PROP_FPS) or 25.0
    frame_rate = max(frame_rate, 1.0)
    interval = (
        int(frame_rate) if sample_fps is None else max(int(frame_rate / sample_fps), 1)
    )
    from .json_safe import finite_float, json_safe_payload

    predictor = get_adult_emotion_predictor()
    predictions: list[dict[str, Any]] = []
    frame_num = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_num % interval == 0:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = predictor.predict_pil(Image.fromarray(rgb))
                label = str(result.get("class") or "")
                conf = finite_float(result.get("confidence"), 0.0)
                predictions.append(
                    {
                        "frame_num": frame_num,
                        "time_sec": round(frame_num / frame_rate, 3),
                        "label": str(result.get("prediction") or label),
                        "confidence": conf,
                        "architecture_votes": result.get("architecture_votes"),
                        "architecture_confidences": json_safe_payload(
                            result.get("architecture_confidences")
                        ),
                    }
                )
                if max_frames is not None and len(predictions) >= max_frames:
                    break
            frame_num += 1
    finally:
        cap.release()

    if not predictions:
        return {
            "error": "no_frames",
            "frames": [],
            "summary": {},
            "dominant": None,
            "frame_count": 0,
        }

    from collections import Counter, defaultdict

    labels = [p["label"] for p in predictions if p.get("label")]
    dominant = Counter(labels).most_common(1)[0][0] if labels else None

    confs = [
        finite_float(p.get("confidence"), 0.0)
        for p in predictions
        if p.get("label") == dominant
    ]
    mean_conf = finite_float(
        sum(confs) / len(confs) if confs else 0.0,
        0.0,
    )

    arch_label_counts: dict[str, Counter] = defaultdict(Counter)
    arch_conf_lists: dict[str, list[float]] = defaultdict(list)
    for frame in predictions:
        per_arch = frame.get("architecture_votes")
        per_conf = frame.get("architecture_confidences")
        if not isinstance(per_arch, dict):
            continue
        for arch, lbl in per_arch.items():
            arch_label_counts[arch][lbl] += 1
            if isinstance(per_conf, dict) and arch in per_conf:
                arch_conf_lists[arch].append(float(per_conf[arch]))

    arch_votes: dict[str, str] = {}
    arch_conf: dict[str, float] = {}
    for arch, counts in arch_label_counts.items():
        top_label, _ = counts.most_common(1)[0]
        arch_votes[arch] = top_label
        confs_arch = arch_conf_lists.get(arch) or []
        from .json_safe import finite_float

        arch_conf[arch] = finite_float(
            sum(confs_arch) / len(confs_arch) if confs_arch else 0.0,
            0.0,
        )

    model_predictions = _model_predictions_payload(arch_votes, arch_conf)
    hard_vote_labels = [row["label"] for row in model_predictions]
    if hard_vote_labels:
        majority_label, majority_count = Counter(hard_vote_labels).most_common(1)[0]
        if majority_count >= 2:
            dominant = majority_label
            from .json_safe import finite_float

            mean_conf = finite_float(
                np.mean(
                    [
                        row["confidence"]
                        for row in model_predictions
                        if row["label"] == majority_label
                    ]
                ),
                mean_conf,
            )

    return {
        "status": "success",
        "modality": "video",
        "prediction": dominant,
        "dominant": dominant,
        "confidence": round(finite_float(mean_conf, 0.0), 4),
        "frame_count": len(predictions),
        "frames": [
            {
                "frame_num": p.get("frame_num"),
                "time_sec": p.get("time_sec"),
                "label": p.get("label"),
                "confidence": finite_float(p.get("confidence"), 0.0),
            }
            for p in predictions
        ],
        "model_predictions": model_predictions,
        "majority_vote_label": dominant,
        "model": "tri_architecture_ensemble",
    }
