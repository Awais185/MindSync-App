"""
When OpenFace returns no usable AUs (common on phone camera uploads),
fill scores from the same emotion models used by /api/analyze-video/ (web).
"""

from __future__ import annotations

import logging
from typing import Any

from .au_emotion_pipeline import STATE_AUS

logger = logging.getLogger(__name__)

# HuggingFace / chat labels -> MindSync dominant + score weights (0–100)
_LABEL_MAP: dict[str, tuple[str, int, int, int]] = {
    "angry": ("stress", 72, 28, 18),
    "anger": ("stress", 72, 28, 18),
    "disgust": ("stress", 55, 35, 22),
    "fear": ("anxiety", 38, 75, 30),
    "fearful": ("anxiety", 38, 75, 30),
    "sad": ("depression", 32, 40, 72),
    "sadness": ("depression", 32, 40, 72),
    "surprise": ("anxiety", 40, 58, 25),
    "happy": ("neutral", 18, 15, 12),
    "happiness": ("neutral", 18, 15, 12),
    "neutral": ("neutral", 12, 12, 12),
}


def openface_results_weak(scores: dict[str, Any]) -> bool:
    active = scores.get("active_aus") or []
    if isinstance(active, list) and len(active) > 0:
        return False
    visibility = float(scores.get("face_visibility_ratio") or 0.0)
    if visibility >= 0.05:
        return False
    max_score = int(scores.get("max_score") or 0)
    if max_score >= 8:
        return False
    return True


def _scores_from_label(label: str, confidence: float) -> dict[str, Any]:
    key = (label or "neutral").strip().lower().replace(" ", "_")
    dominant, stress, anxiety, depression = _LABEL_MAP.get(
        key, ("neutral", 20, 20, 20)
    )
    conf = max(0.15, min(1.0, float(confidence or 0.5)))
    scale = 0.55 + 0.45 * conf
    stress_i = int(round(stress * scale))
    anx_i = int(round(anxiety * scale))
    dep_i = int(round(depression * scale))
    max_score = max(stress_i, anx_i, dep_i)
    return {
        "stress_score": stress_i,
        "anxiety_score": anx_i,
        "depression_score": dep_i,
        "dominant_state": dominant,
        "dominant_states": [dominant] if dominant != "neutral" else [],
        "max_score": max_score,
        "active_aus": [],
        "au_disease_table": dict(STATE_AUS),
        "matched_aus_by_state": {},
        "state_probabilities": {
            "stress": stress_i / 100.0,
            "anxiety": anx_i / 100.0,
            "depression": dep_i / 100.0,
        },
        "face_visibility_ratio": conf,
        "au_summary": [],
        "recommendations": [
            f"Emotion model detected «{label}» (web-style scan) — OpenFace had no face landmarks in this clip.",
            "For AU landmarks, re-record with face centered and good lighting, then try High Accuracy mode.",
        ],
        "behavioral_insights": [
            f"Dominant expression signal: {label} ({int(conf * 100)}% confidence).",
        ],
        "analysis_source": "emotion_model_fallback",
    }


def _pick_from_deepface(deepface: dict[str, Any]) -> tuple[str, float] | None:
    dominant = (deepface.get("dominant") or "").strip()
    if dominant:
        frames = deepface.get("frames") or []
        conf = 0.55
        if isinstance(frames, list) and frames:
            for fr in frames:
                if str(fr.get("label", "")).lower() == dominant.lower():
                    conf = float(fr.get("confidence") or conf)
                    break
        summary = deepface.get("summary") or {}
        if isinstance(summary, dict) and summary:
            total = sum(int(v) for v in summary.values()) or 1
            conf = max(conf, int(summary.get(dominant, 0)) / total)
        return dominant, conf

    summary = deepface.get("summary") or {}
    if isinstance(summary, dict) and summary:
        top = max(summary.items(), key=lambda kv: int(kv[1]))
        total = sum(int(v) for v in summary.values()) or 1
        return str(top[0]), int(top[1]) / total
    return None


def _pick_from_chat_video(chat: dict[str, Any]) -> tuple[str, float] | None:
    pred = (chat.get("prediction") or "").strip()
    if not pred or pred.lower() == "unknown":
        return None
    conf = float(chat.get("confidence") or 0.5)
    return pred, conf


def merge_emotion_fallback(
    openface_scores: dict[str, Any],
    *,
    deepface_video: dict[str, Any] | None = None,
    chat_video: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Return openface_scores unchanged if strong; otherwise overlay web-style emotion scores.
    """
    if not openface_results_weak(openface_scores):
        return openface_scores

    picked: tuple[str, float] | None = None
    if deepface_video:
        picked = _pick_from_deepface(deepface_video)
    if picked is None and chat_video:
        picked = _pick_from_chat_video(chat_video)
    if picked is None:
        logger.warning(
            "[MindSync] OpenFace weak and emotion fallback found no frames — keeping neutral scores"
        )
        return openface_scores

    label, conf = picked
    merged = dict(openface_scores)
    merged.update(_scores_from_label(label, conf))
    logger.info(
        "[MindSync] Emotion fallback applied: label=%s conf=%.2f dominant=%s",
        label,
        conf,
        merged.get("dominant_state"),
    )
    return merged
