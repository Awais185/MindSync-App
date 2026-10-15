"""
MediaPipe Face Mesh → geometric AU proxies → :mod:`au_emotion_pipeline` scoring.

Landmarks are drawn on the output video; AU intensities are merged with emotion-model
signals in :mod:`video_au_tracker`.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import cv2
import numpy as np

logger = logging.getLogger(__name__)

_MP = None
_DRAWING = None
_FACE_MESH_MODULE = None
_MESH_CTX: Any | None = None


def mediapipe_available() -> bool:
    try:
        _ensure_mediapipe()
        return True
    except Exception:
        return False


def warmup_face_mesh() -> bool:
    """Create FaceMesh once so the first analyze request is not blocked on import."""
    if not mediapipe_available():
        return False
    _get_face_mesh()
    return True


def _ensure_mediapipe() -> None:
    global _MP, _DRAWING, _FACE_MESH_MODULE
    if _MP is not None:
        return
    import mediapipe as mp

    _MP = mp
    _DRAWING = mp.solutions.drawing_utils
    _FACE_MESH_MODULE = mp.solutions.face_mesh


def _get_face_mesh():
    global _MESH_CTX
    _ensure_mediapipe()
    if _MESH_CTX is None:
        _MESH_CTX = _FACE_MESH_MODULE.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    return _MESH_CTX


def close_face_mesh() -> None:
    global _MESH_CTX
    if _MESH_CTX is not None:
        try:
            _MESH_CTX.close()
        except Exception:
            pass
        _MESH_CTX = None


@dataclass
class MeshFrameResult:
    aus: dict[str, float]
    landmarks: Any | None
    face_rect: tuple[int, int, int, int] | None


def _pt(landmarks, idx: int, w: int, h: int) -> np.ndarray:
    lm = landmarks[idx]
    return np.array([lm.x * w, lm.y * h], dtype=np.float64)


def _dist(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def _clip01(x: float) -> float:
    return float(max(0.0, min(1.0, x)))


def landmarks_to_au_proxies(landmarks, width: int, height: int) -> dict[str, float]:
    """
    Map 468-point face mesh to MindSync AU intensities (0–1).
    Geometry is normalized by inter-pupil distance.
    """
    left_eye_in, right_eye_in = 133, 362
    mouth_l, mouth_r = 61, 291
    upper_lip, lower_lip = 13, 14
    chin = 152
    nose_tip = 1
    brow_inner_l, brow_inner_r = 107, 336
    brow_outer_l, brow_outer_r = 46, 276
    lid_top_l, lid_bot_l = 159, 145
    lid_top_r, lid_bot_r = 386, 374

    le = _pt(landmarks, left_eye_in, width, height)
    re = _pt(landmarks, right_eye_in, width, height)
    scale = max(_dist(le, re), 1.0)

    ml = _pt(landmarks, mouth_l, width, height)
    mr = _pt(landmarks, mouth_r, width, height)
    ul = _pt(landmarks, upper_lip, width, height)
    ll = _pt(landmarks, lower_lip, width, height)
    ch = _pt(landmarks, chin, width, height)
    nt = _pt(landmarks, nose_tip, width, height)

    bil = _pt(landmarks, brow_inner_l, width, height)
    bir = _pt(landmarks, brow_inner_r, width, height)
    bol = _pt(landmarks, brow_outer_l, width, height)
    bor = _pt(landmarks, brow_outer_r, width, height)
    etl = _pt(landmarks, lid_top_l, width, height)
    etr = _pt(landmarks, lid_top_r, width, height)

    mouth_open = _dist(ul, ll) / scale
    mouth_width = _dist(ml, mr) / scale
    lip_corner_drop = ((ml[1] + mr[1]) / 2.0 - (ul[1] + ll[1]) / 2.0) / scale

    inner_brow_raise = (
        (etl[1] - bil[1]) + (etr[1] - bir[1])
    ) / (2.0 * scale)
    outer_brow_raise = (
        (etl[1] - bol[1]) + (etr[1] - bor[1])
    ) / (2.0 * scale)
    brow_eye_gap = (
        _dist(bil, etl) + _dist(bir, etr)
    ) / (2.0 * scale)

    eye_h_l = abs(_pt(landmarks, lid_top_l, width, height)[1] - _pt(landmarks, lid_bot_l, width, height)[1])
    eye_h_r = abs(_pt(landmarks, lid_top_r, width, height)[1] - _pt(landmarks, lid_bot_r, width, height)[1])
    eye_open = (eye_h_l + eye_h_r) / (2.0 * scale)

    aus: dict[str, float] = {}
    aus["AU25"] = _clip01((mouth_open - 0.10) / 0.32)
    aus["AU26"] = _clip01((mouth_open - 0.20) / 0.40)
    aus["AU12"] = _clip01((mouth_width - 0.72) / 0.32)
    aus["AU15"] = _clip01((lip_corner_drop - 0.015) / 0.11)
    aus["AU01"] = _clip01((inner_brow_raise - 0.06) / 0.14)
    aus["AU02"] = _clip01((outer_brow_raise - 0.05) / 0.13)
    aus["AU04"] = _clip01((0.38 - brow_eye_gap) / 0.10)
    aus["AU05"] = _clip01((eye_open - 0.22) / 0.12)
    smile = aus["AU12"]
    aus["AU06"] = _clip01(smile * 0.65 + (0.26 - eye_open) / 0.14 * 0.35)
    aus["AU45"] = _clip01((0.15 - eye_open) / 0.09)
    aus["AU17"] = _clip01(((ch[1] - nt[1]) / scale - 0.42) / 0.18)
    aus["AU20"] = _clip01((mouth_width - 0.82) / 0.22) * _clip01(mouth_open / 0.18)

    return {k: v for k, v in aus.items() if v > 0.05}


def _landmark_bounds(landmarks, w: int, h: int) -> tuple[int, int, int, int]:
    xs = [lm.x * w for lm in landmarks]
    ys = [lm.y * h for lm in landmarks]
    x0, x1 = int(min(xs)), int(max(xs))
    y0, y1 = int(min(ys)), int(max(ys))
    return x0, y0, max(1, x1 - x0), max(1, y1 - y0)


def process_bgr_frame(bgr: np.ndarray) -> MeshFrameResult:
    h, w = bgr.shape[:2]
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    mesh = _get_face_mesh()
    results = mesh.process(rgb)
    if not results.multi_face_landmarks:
        return MeshFrameResult(aus={}, landmarks=None, face_rect=None)

    face_lms = results.multi_face_landmarks[0]
    aus = landmarks_to_au_proxies(face_lms.landmark, w, h)
    rect = _landmark_bounds(face_lms.landmark, w, h)
    return MeshFrameResult(aus=aus, landmarks=face_lms, face_rect=rect)


def draw_mesh_on_bgr(bgr: np.ndarray, face_landmarks) -> np.ndarray:
    if face_landmarks is None:
        return bgr
    _ensure_mediapipe()
    out = bgr.copy()
    rgb = cv2.cvtColor(out, cv2.COLOR_BGR2RGB)
    _DRAWING.draw_landmarks(
        image=rgb,
        landmark_list=face_landmarks,
        connections=_FACE_MESH_MODULE.FACEMESH_CONTOURS,
        landmark_drawing_spec=_DRAWING.DrawingSpec(color=(0, 255, 200), thickness=1, circle_radius=1),
        connection_drawing_spec=_DRAWING.DrawingSpec(color=(80, 180, 255), thickness=1),
    )
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


# Mesh geometry is authoritative for these; emotion model fills the rest.
_MESH_PRIMARY_AUS = frozenset(
    {
        "AU01",
        "AU02",
        "AU04",
        "AU05",
        "AU06",
        "AU12",
        "AU15",
        "AU17",
        "AU20",
        "AU25",
        "AU26",
        "AU45",
    }
)
_EMOTION_PRIMARY_AUS = frozenset({"AU07", "AU09", "AU10", "AU14", "AU23"})


def merge_au_dicts(
    emotion_aus: dict[str, float],
    mesh_aus: dict[str, float],
) -> dict[str, float]:
    """Blend emotion-derived and mesh-derived AUs for :mod:`au_emotion_pipeline` scoring."""
    merged: dict[str, float] = {}
    keys = set(emotion_aus) | set(mesh_aus)
    for au in keys:
        e = float(emotion_aus.get(au, 0.0))
        m = float(mesh_aus.get(au, 0.0))
        if au in _EMOTION_PRIMARY_AUS:
            merged[au] = max(e, m * 0.35)
        elif au in _MESH_PRIMARY_AUS:
            if m >= 0.12:
                merged[au] = m
            else:
                merged[au] = max(m, e * 0.45)
        else:
            merged[au] = max(e, m)
    return merged
