"""
Real-time facial emotion / distress scoring from Action Unit (AU) intensities.

OpenFace (and similar) may emit keys with whitespace or a trailing ``_r`` suffix.
All downstream logic consumes only :func:`normalize_aus` output.
"""

from __future__ import annotations

import logging
import math
import re
from typing import Any

logger = logging.getLogger(__name__)

# --- Module-level constants (do not move into functions) ---

EXPECTED_AUS: list[str] = [
    "AU01",
    "AU02",
    "AU04",
    "AU05",
    "AU06",
    "AU07",
    "AU09",
    "AU10",
    "AU12",
    "AU14",
    "AU15",
    "AU17",
    "AU20",
    "AU23",
    "AU25",
    "AU26",
    "AU45",
]

AU_WEIGHTS: dict[str, float] = {
    "AU04": 1.5,
    "AU14": 1.5,
    "AU06": 1.2,
    "AU12": 1.2,
}
DEFAULT_WEIGHT: float = 1.0

STATE_AUS: dict[str, list[str]] = {
    "stress": ["AU01", "AU04", "AU06", "AU10", "AU14", "AU15"],
    "anxiety": ["AU02", "AU04", "AU09", "AU25", "AU45"],
    "depression": ["AU06", "AU12", "AU15", "AU17", "AU26"],
}

_AU_CODE_RE = re.compile(r"^AU\d{2}$", re.IGNORECASE)

# Short hints for behavioral_insights strings
_AU_HINTS: dict[str, str] = {
    "AU01": "AU01 (inner brow raise) — surprise or worry",
    "AU02": "AU02 (outer brow raise) — fear or distress",
    "AU04": "AU04 (brow lowerer) — cognitive load or frustration",
    "AU05": "AU05 (upper lid raise) — fear or heightened attention",
    "AU06": "AU06 (cheek raise) — positive engagement or strain",
    "AU07": "AU07 (lid tightener) — tension or concentration",
    "AU09": "AU09 (nose wrinkle) — disgust or aversion",
    "AU10": "AU10 (upper lip raise) — disgust or contempt",
    "AU12": "AU12 (lip corner pull) — smile or social masking",
    "AU14": "AU14 (dimpler) — smirk or controlled expression",
    "AU15": "AU15 (lip corner depressor) — sadness or low mood",
    "AU17": "AU17 (chin raise) — pride or defiance",
    "AU20": "AU20 (lip stretch) — fear or uncertainty",
    "AU23": "AU23 (lip tighten) — anger control",
    "AU25": "AU25 (lips part) — speech readiness or anxiety",
    "AU26": "AU26 (jaw drop) — surprise or fatigue",
    "AU45": "AU45 (blink) — stress or eye strain",
}


def normalize_aus(raw_aus: dict[Any, Any]) -> dict[str, float]:
    """
    Strip whitespace from keys, normalize ``AUxx_r`` → ``AUxx``, cast to float,
    drop non-positive intensities.
    """
    out: dict[str, float] = {}
    if not raw_aus:
        return out
    for raw_key, raw_val in raw_aus.items():
        key = "".join(str(raw_key).split())
        if key.lower().endswith("_r"):
            key = key[:-2]
        key = key.upper()
        if not _AU_CODE_RE.match(key):
            continue
        try:
            val = float(raw_val)
        except (TypeError, ValueError):
            continue
        if val <= 0.0:
            continue
        out[key] = val
    return out


def compute_visibility(aus: dict[str, float]) -> float:
    if not aus:
        return 0.0
    visible = sum(1 for au in EXPECTED_AUS if au in aus)
    ratio = visible / float(len(EXPECTED_AUS)) if EXPECTED_AUS else 0.0
    if ratio == 0.0 and len(aus) > 0:
        ratio = 0.1
    return float(ratio)


def compute_scores(aus: dict[str, float]) -> dict[str, float]:
    """Per-state probability in (0, 1) from weighted AU sums + sigmoid; 0.0 if no AUs for that state."""
    out: dict[str, float] = {}
    for state, au_list in STATE_AUS.items():
        present = [au for au in au_list if au in aus]
        if not present:
            out[state] = 0.0
            continue
        raw_score = sum(
            aus[au] * AU_WEIGHTS.get(au, DEFAULT_WEIGHT) for au in present
        )
        scaled = (raw_score / 5.0) - 1.5
        out[state] = 1.0 / (1.0 + math.exp(-scaled))
    return out


def get_dominant_state(scores: dict[str, float]) -> str:
    if not scores:
        return "neutral"
    dominant = max(scores, key=lambda k: scores.get(k, 0.0))
    if scores.get(dominant, 0.0) < 0.2:
        return "neutral"
    return dominant


def get_matched_aus(aus: dict[str, float]) -> dict[str, dict[str, float]]:
    matched: dict[str, dict[str, float]] = {}
    for state, au_list in STATE_AUS.items():
        inner: dict[str, float] = {}
        for au in au_list:
            if au not in aus:
                continue
            v = float(aus[au])
            if v <= 0.0:
                continue
            inner[au] = v
        matched[state] = inner
    return matched


def build_au_summary(aus: dict[str, float]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for au, intensity in aus.items():
        if intensity <= 0.0:
            continue
        w = float(AU_WEIGHTS.get(au, DEFAULT_WEIGHT))
        rows.append({"au": au, "intensity": float(intensity), "weight": w})
    rows.sort(key=lambda r: float(r["intensity"]), reverse=True)
    return rows


def _build_behavioral_insights(aus: dict[str, float], au_summary: list[dict[str, Any]]) -> list[str]:
    insights: list[str] = []
    for row in au_summary[:6]:
        au = str(row.get("au") or "")
        hint = _AU_HINTS.get(au, f"{au} active in this frame")
        intensity = float(row.get("intensity") or 0.0)
        insights.append(f"{hint} — intensity {intensity:.2f}")
    if not insights and not aus:
        insights.append("No AU signal in frame — face may be occluded or not tracked.")
    elif not insights:
        insights.append("Facial behavior appears relatively stable in this scan.")
    return insights


def _build_recommendations(dominant: str, scores: dict[str, float]) -> list[str]:
    s = float(scores.get("stress") or 0.0)
    a = float(scores.get("anxiety") or 0.0)
    d = float(scores.get("depression") or 0.0)
    recs: list[str] = []

    if dominant == "neutral":
        recs.append("Nice work keeping expressions balanced — keep short mindful breaks during screen time.")
        return recs

    if dominant == "stress":
        if s > 0.6:
            recs.append("High stress pattern: try a 5-minute guided breathing exercise and reduce multitasking.")
            recs.append("Step away from the screen for two minutes; unclench jaw and drop shoulders.")
        elif s > 0.0:
            recs.append("Mild stress load detected: schedule a 3-minute stretch and hydrate before the next task.")

    if dominant == "anxiety":
        if a > 0.6:
            recs.append("Elevated anxiety signal: use box breathing (4-4-4-4) and ground with 5-4-3-2-1 senses.")
        elif a > 0.0:
            recs.append("Light anxiety cues: slow your scroll pace and fix gaze on a distant object for 20 seconds.")

    if dominant == "depression":
        recs.append("Low-energy facial pattern: consider a brief walk or daylight exposure; reach out if mood stays low.")

    if dominant not in {"stress", "anxiety", "depression"}:
        recs.append("Take a short break and check in with how your body feels before continuing.")

    if not recs:
        recs.append("Maintain steady breaks; small resets help regulate facial tension over time.")
    return recs


def analyze_frame(raw_aus: dict[Any, Any]) -> dict[str, Any]:
    """
    Master pipeline: normalize → visibility → summary → scores → dominant → matched → insights.
    """
    aus = normalize_aus(raw_aus)
    visibility = compute_visibility(aus)
    au_summary = build_au_summary(aus)
    scores = compute_scores(aus)
    dominant = get_dominant_state(scores)
    matched = get_matched_aus(aus)
    active_aus = sorted(aus.keys())
    recommendations = _build_recommendations(dominant, scores)
    behavioral_insights = _build_behavioral_insights(aus, au_summary)

    if not aus:
        print("[MindSync] NO FACE IN FRAME - no AUs in frame", flush=True)

    logger.info(
        "[MindSync] AU count:%s | stress:%.2f | anxiety:%.2f | depression:%.2f | dominant:%s | visibility:%.2f",
        len(aus),
        scores.get("stress", 0.0),
        scores.get("anxiety", 0.0),
        scores.get("depression", 0.0),
        dominant,
        visibility,
    )
    print(
        f"[MindSync] AU count:{len(aus)} | stress:{scores.get('stress', 0.0):.2f} | "
        f"anxiety:{scores.get('anxiety', 0.0):.2f} | depression:{scores.get('depression', 0.0):.2f} | "
        f"dominant:{dominant} | visibility:{visibility:.2f}",
        flush=True,
    )

    return {
        "stress_score": scores["stress"],
        "anxiety_score": scores["anxiety"],
        "depression_score": scores["depression"],
        "dominant_state": dominant,
        "state_probabilities": scores,
        "face_visibility_ratio": visibility,
        "active_aus": active_aus,
        "au_summary": au_summary,
        "matched_aus_by_state": matched,
        "recommendations": recommendations,
        "behavioral_insights": behavioral_insights,
    }
