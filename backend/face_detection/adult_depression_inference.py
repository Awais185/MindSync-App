"""
MindSync adult depression model — OpenFace AU CSV → MLP probabilities.

Weights are loaded from ``depression_inference_weights.npz`` (exported from the
training joblib bundle) so inference works without unpickling sklearn RNG state.
"""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from django.conf import settings

logger = logging.getLogger(__name__)

CLASS_NAMES = {
    0: "Healthy",
    1: "Mild",
    2: "Moderate",
    3: "Severe",
}

DEFAULT_WINDOW_FRAMES = 150

_RESEARCH_WARNING = (
    "Research estimate only; not a clinical diagnosis. "
    "Percentages are model probabilities, not validated clinical risk scores."
)


def adult_depression_model_dir() -> Path:
    raw = getattr(settings, "ADULT_DEPRESSION_MODEL_DIR", None)
    if raw:
        return Path(raw).expanduser().resolve()
    return (
        Path(settings.BASE_DIR) / "models" / "Adult depression detection" / "model"
    ).resolve()


def _relu(x: np.ndarray) -> np.ndarray:
    return np.maximum(x, 0.0, dtype=x.dtype)


def _softmax(x: np.ndarray) -> np.ndarray:
    x = x - np.max(x, axis=-1, keepdims=True)
    e = np.exp(x)
    return e / np.sum(e, axis=-1, keepdims=True)


@lru_cache(maxsize=1)
def _load_joblib_model():
    from .depression_joblib_loader import load_depression_joblib_bundle

    bundle = load_depression_joblib_bundle()
    return bundle["model"], list(bundle["features"]), bundle


@lru_cache(maxsize=1)
def _load_weights() -> dict[str, Any]:
    model_dir = adult_depression_model_dir()
    npz_path = model_dir / "depression_inference_weights.npz"
    if not npz_path.exists():
        raise FileNotFoundError(
            f"Depression weights not found: {npz_path}. "
            "Run face_detection/export_depression_npz.py after updating the joblib bundle."
        )
    card_path = model_dir / "model_card.json"
    features: list[str] = []
    class_map = dict(CLASS_NAMES)
    if card_path.exists():
        card = json.loads(card_path.read_text(encoding="utf-8"))
        features = list(card.get("features") or [])
        raw_classes = card.get("classes") or {}
        if isinstance(raw_classes, dict):
            class_map = {int(k): str(v) for k, v in raw_classes.items()}

    data = np.load(npz_path, allow_pickle=True)
    if not features:
        features = [str(x) for x in data["features"].tolist()]

    coefs = [
        np.asarray(data["coefs_0"], dtype=np.float32),
        np.asarray(data["coefs_1"], dtype=np.float32),
        np.asarray(data["coefs_2"], dtype=np.float32),
    ]
    intercepts = [
        np.asarray(data["intercepts_0"], dtype=np.float32),
        np.asarray(data["intercepts_1"], dtype=np.float32),
        np.asarray(data["intercepts_2"], dtype=np.float32),
    ]

    return {
        "features": features,
        "class_names": class_map,
        "mean_": np.asarray(data["mean_"], dtype=np.float64),
        "scale_": np.asarray(data["scale_"], dtype=np.float64),
        "coefs": coefs,
        "intercepts": intercepts,
        "classes_": np.asarray(data.get("classes_", [0, 1, 2, 3]), dtype=np.int64),
    }


def predict_proba_matrix(X: np.ndarray) -> np.ndarray:
    try:
        model, _, _bundle = _load_joblib_model()
        return model.predict_proba(np.asarray(X, dtype=np.float64))
    except Exception as exc:
        logger.warning("Joblib depression model unavailable (%s); using npz weights.", exc)
        bundle = _load_weights()
        Xf = np.asarray(X, dtype=np.float32)
        mean = np.asarray(bundle["mean_"], dtype=np.float32)
        scale = np.asarray(bundle["scale_"], dtype=np.float32)
        scale_safe = np.where(scale == 0, 1.0, scale)
        Xs = (Xf - mean) / scale_safe
        h = _relu(Xs @ bundle["coefs"][0].T + bundle["intercepts"][0])
        h = _relu(h @ bundle["coefs"][1].T + bundle["intercepts"][1])
        logits = h @ bundle["coefs"][2].T + bundle["intercepts"][2]
        return _softmax(np.asarray(logits, dtype=np.float64))


def preprocess_openface_csv(csv_path: str | Path) -> tuple[np.ndarray, int, int]:
    bundle = _load_weights()
    feature_names = bundle["features"]
    df = pd.read_csv(csv_path, low_memory=False, on_bad_lines="skip")
    df.columns = [str(c).strip() for c in df.columns]
    if df.empty:
        raise ValueError("The OpenFace CSV contains no frames.")

    missing = [c for c in feature_names if c not in df.columns]
    if missing:
        raise ValueError(
            f"Missing {len(missing)} required AU columns for depression model."
        )

    X = df[feature_names].apply(pd.to_numeric, errors="coerce")
    X = X.replace([np.inf, -np.inf], np.nan)
    valid = X.notna().all(axis=1)
    X = X.loc[valid].astype(np.float32)
    dropped = int(len(df) - len(X))
    if len(X) == 0:
        raise ValueError("No frames have complete numeric AU features.")
    return X.to_numpy(), len(df), dropped


def _scores_from_probabilities(
    mean_prob: np.ndarray,
    classes: np.ndarray,
    class_names: dict[int, str],
) -> dict[str, Any]:
    probs = {int(c): float(mean_prob[j]) for j, c in enumerate(classes)}
    pct = {
        class_names.get(int(c), f"Class_{c}"): round(probs[int(c)] * 100.0, 2)
        for c in classes
    }
    best_id = int(classes[int(np.argmax(mean_prob))])
    label = class_names.get(best_id, f"Class_{best_id}")

    # Map severity to 0–100 dashboard scores (depression primary; stress/anxiety aligned).
    severity = (
        probs.get(0, 0.0) * 12.0
        + probs.get(1, 0.0) * 38.0
        + probs.get(2, 0.0) * 62.0
        + probs.get(3, 0.0) * 88.0
    )
    dep_i = int(round(severity))
    stress_i = int(round(min(100, severity * 0.92)))
    anx_i = int(round(min(100, severity * 0.85)))

    dominant = "depression" if best_id >= 2 else ("anxiety" if best_id == 1 else "neutral")

    return {
        "stress_score": stress_i,
        "anxiety_score": anx_i,
        "depression_score": dep_i,
        "dominant_state": dominant,
        "dominant_states": [dominant] if dominant != "neutral" else [],
        "max_score": max(stress_i, anx_i, dep_i),
        "depression_model": {
            "predicted_label": label,
            "predicted_class_id": best_id,
            "average_class_probabilities_percent": pct,
            "warning": _RESEARCH_WARNING,
        },
        "analysis_source": "adult_depression_mlp",
        "active_aus": [],
        "au_disease_table": {},
        "matched_aus_by_state": {},
        "state_probabilities": pct,
        "face_visibility_ratio": 0.0,
        "au_summary": [],
        "recommendations": [_RESEARCH_WARNING],
        "behavioral_insights": [],
    }


def predict_openface_csv(
    csv_path: str | Path,
    *,
    window_frames: int = DEFAULT_WINDOW_FRAMES,
) -> dict[str, Any]:
    X, total_frames, dropped = preprocess_openface_csv(csv_path)
    probabilities = predict_proba_matrix(X.astype(np.float64))
    try:
        _model, feature_names, bundle = _load_joblib_model()
        classes = np.asarray(
            getattr(_model, "classes_", bundle.get("classes", [0, 1, 2, 3]))
        )
        card = bundle.get("card", {}).get("classes", {}) if isinstance(bundle.get("card"), dict) else {}
        class_names = (
            {int(k): str(v) for k, v in card.items()}
            if card
            else dict(CLASS_NAMES)
        )
    except Exception:
        bundle = _load_weights()
        classes = bundle["classes_"]
        class_names = bundle["class_names"]

    overall_prob = probabilities.mean(axis=0)
    out = _scores_from_probabilities(overall_prob, classes, class_names)
    out["depression_model"]["total_frames"] = total_frames
    out["depression_model"]["valid_frames"] = int(len(X))
    out["depression_model"]["dropped_frames"] = dropped
    out["depression_model"]["window_frames"] = int(window_frames)

    if window_frames > 0 and len(probabilities) > 0:
        windows: list[dict[str, Any]] = []
        for start in range(0, len(probabilities), window_frames):
            end = min(start + window_frames, len(probabilities))
            wprob = probabilities[start:end].mean(axis=0)
            win = _scores_from_probabilities(wprob, classes, class_names)
            windows.append(
                {
                    "start_frame": start,
                    "end_frame_exclusive": end,
                    "predicted_label": win["depression_model"]["predicted_label"],
                    "probabilities_percent": win["depression_model"][
                        "average_class_probabilities_percent"
                    ],
                }
            )
        out["depression_model"]["windows"] = windows

    return out


def mental_health_scores_from_depression(summary: dict[str, Any]) -> tuple[int, int, int]:
    return (
        int(summary.get("stress_score") or 0),
        int(summary.get("anxiety_score") or 0),
        int(summary.get("depression_score") or 0),
    )
