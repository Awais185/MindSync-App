from __future__ import annotations

import logging
from typing import Any

import pandas as pd

logger = logging.getLogger(__name__)

# Legacy AU formula pipeline removed — depression uses trained MLP on CSV features.


def _openface_metadata_only(csv_path: str) -> dict[str, Any]:
    """OpenFace ran successfully; no AU formula scores (e.g. users under 16)."""
    df = pd.read_csv(csv_path, on_bad_lines="skip")
    visibility = 0.0
    if "success" in df.columns:
        try:
            visibility = float(df["success"].astype(float).mean())
        except Exception:
            pass
    elif len(df) > 0:
        visibility = 1.0

    return {
        "stress_score": 0,
        "anxiety_score": 0,
        "depression_score": 0,
        "dominant_state": "neutral",
        "dominant_states": [],
        "max_score": 0,
        "active_aus": [],
        "au_disease_table": {},
        "matched_aus_by_state": {},
        "state_probabilities": {},
        "face_visibility_ratio": visibility,
        "au_summary": [],
        "recommendations": [],
        "behavioral_insights": [],
        "analysis_source": "openface_metadata_only",
        "adult_ml_skipped": True,
    }


def analyze_openface_csv(
    csv_path: str,
    *,
    use_depression_model: bool = False,
) -> dict[str, Any]:
    """
    Score OpenFace CSV output.

    When ``use_depression_model`` is True, runs the adult depression MLP.
    Otherwise returns neutral scores with face visibility metadata only.
    """
    if use_depression_model:
        from .adult_depression_inference import predict_openface_csv

        scores = predict_openface_csv(csv_path)
        try:
            df = pd.read_csv(csv_path, on_bad_lines="skip")
            if "success" in df.columns:
                scores["face_visibility_ratio"] = float(
                    df["success"].astype(float).mean()
                )
        except Exception:
            logger.debug("Could not compute face visibility from CSV", exc_info=True)
        return scores

    return _openface_metadata_only(csv_path)
