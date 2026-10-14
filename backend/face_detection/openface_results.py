from __future__ import annotations

import logging
from typing import Any

import pandas as pd

from .au_emotion_pipeline import STATE_AUS, analyze_frame

logger = logging.getLogger(__name__)

# Backward-compatible alias (older code referenced AU_DISEASE_TABLE).
AU_DISEASE_TABLE: dict[str, list[str]] = STATE_AUS


def analyze_openface_csv(csv_path: str) -> dict[str, Any]:
    """
    Accepts OpenFace CSV path, aggregates per-AU means, runs :func:`analyze_frame`,
    and returns legacy int scores (0–100) plus structured pipeline fields.

    Raw column names (e.g. ``AU04_r``) are passed through; normalization happens
    inside :func:`analyze_frame` via :func:`normalize_aus`.
    """
    df = pd.read_csv(csv_path, on_bad_lines="skip")

    raw_aus: dict[str, float] = {}
    intensity_cols: list[str] = []
    for col in df.columns:
        col_s = str(col).strip()
        if col_s.endswith("_r") or col_s.endswith("_c"):
            intensity_cols.append(col)
    if not intensity_cols:
        for col in df.columns:
            col_s = str(col).strip()
            if col_s.upper().startswith("AU") and col_s[2:4].isdigit():
                intensity_cols.append(col)
    for col in intensity_cols:
        try:
            series = df[col].fillna(0).astype(float)
            # Phone clips: face may appear in few frames — max captures peaks better than mean.
            intensity = float(series.max()) if len(series) else 0.0
            if intensity <= 0.0:
                intensity = float(series.mean())
        except Exception:
            continue
        raw_aus[col] = intensity

    frame = analyze_frame(raw_aus)

    p_stress = float(frame["stress_score"])
    p_anx = float(frame["anxiety_score"])
    p_dep = float(frame["depression_score"])

    stress_i = int(round(p_stress * 100))
    anx_i = int(round(p_anx * 100))
    dep_i = int(round(p_dep * 100))
    max_score = max(stress_i, anx_i, dep_i)

    dominant = str(frame["dominant_state"])
    dominant_states: list[str] = [dominant] if dominant != "neutral" else []

    return {
        "stress_score": stress_i,
        "anxiety_score": anx_i,
        "depression_score": dep_i,
        "dominant_state": dominant,
        "dominant_states": dominant_states,
        "max_score": int(max_score),
        "active_aus": list(frame.get("active_aus") or []),
        "au_disease_table": dict(STATE_AUS),
        "matched_aus_by_state": frame["matched_aus_by_state"],
        "state_probabilities": frame["state_probabilities"],
        "face_visibility_ratio": float(frame["face_visibility_ratio"]),
        "au_summary": frame["au_summary"],
        "recommendations": frame["recommendations"],
        "behavioral_insights": frame["behavioral_insights"],
    }
