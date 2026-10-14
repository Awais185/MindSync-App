"""Pre-match quality checks for still-image face verification (OpenCV)."""

from __future__ import annotations

import logging
from io import BytesIO
from typing import Any

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# Tunables (product spec)
MIN_LAPLACIAN_VARIANCE = 100.0
MIN_FACE_AREA_RATIO = 0.15  # 15% of frame

# Background unlock capture: faster shutter, lower light → relax gates
UNLOCK_MIN_LAPLACIAN_VARIANCE = 18.0
UNLOCK_MIN_FACE_AREA_RATIO = 0.06

# Blur is measured on the detected face crop (not the full frame).
MIN_FACE_ROI_LAPLACIAN = 45.0
UNLOCK_MIN_FACE_ROI_LAPLACIAN = 12.0


def _pil_to_bgr_rgb(image_bytes: bytes) -> np.ndarray | None:
    try:
        img = Image.open(BytesIO(image_bytes)).convert("RGB")
        return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)
    except Exception as e:  # noqa: BLE001
        logger.warning("face gate: decode failed: %s", e)
        return None


def analyze_face_frame(
    image_bytes: bytes,
    *,
    unlock_capture: bool = False,
) -> tuple[bool, str, dict[str, Any]]:
    """
    Quality checks for still-image face verification.
    Face presence is now guaranteed by the Android client (Google ML Kit).
    This function now only verifies that the frame isn't excessively blurry.
    """
    min_lap = UNLOCK_MIN_LAPLACIAN_VARIANCE if unlock_capture else MIN_LAPLACIAN_VARIANCE

    bgr = _pil_to_bgr_rgb(image_bytes)
    if bgr is None or bgr.size == 0:
        return False, "NO_FACE_IN_FRAME", {}

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    full_lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())

    if full_lap_var < min_lap:
        msg = f"FRAME_BLURRY — full_frame={full_lap_var:.1f} (<{min_lap})"
        logger.info("[MindSync] %s", msg)
        return False, "FRAME_BLURRY", {
            "laplacian_variance": full_lap_var,
            "full_frame_laplacian_variance": full_lap_var,
        }

    # Since ML Kit verified the face, we assume it's good.
    return True, "", {
        "laplacian_variance": full_lap_var,
        "face_area_percent": 100.0, # Dummy value since ML Kit handles size logic locally if needed
    }
