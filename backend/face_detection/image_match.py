"""Lightweight image similarity helpers (no extra deps beyond Pillow)."""

from __future__ import annotations

import math
from io import BytesIO
from typing import BinaryIO

import numpy as np
from PIL import Image


def _load_and_resize(fileobj: BinaryIO, size: int = 64) -> Image.Image:
    img = Image.open(fileobj).convert("RGB")
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    return img


def normalized_rmse_similarity(a_bytes: bytes, b_bytes: bytes, size: int = 64) -> float:
    """
    Returns a score in [0, 1] where 1 means identical (after resize) and 0 means very different.
    Uses RMSE on normalized pixel values.
    """
    a = _load_and_resize(BytesIO(a_bytes), size=size)
    b = _load_and_resize(BytesIO(b_bytes), size=size)
    pa = list(a.getdata())
    pb = list(b.getdata())
    n = len(pa) * 3  # RGB
    if n == 0:
        return 0.0
    acc = 0.0
    for (ar, ag, ab), (br, bg, bb) in zip(pa, pb):
        acc += (ar - br) ** 2 + (ag - bg) ** 2 + (ab - bb) ** 2
    rmse = math.sqrt(acc / n)  # 0..~255
    # Map RMSE to similarity: lower RMSE -> higher score
    sim = max(0.0, 1.0 - (rmse / 255.0))
    return float(sim)


def cosine_similarity_face_images(a_bytes: bytes, b_bytes: bytes, size: int = 96) -> float:
    """
    Cosine similarity between L2-normalized flattened RGB vectors of resized images.
    Returns a value in [-1, 1]; same-subject photos typically score well above 0.5.
    """
    a = np.asarray(_load_and_resize(BytesIO(a_bytes), size=size), dtype=np.float64)
    b = np.asarray(_load_and_resize(BytesIO(b_bytes), size=size), dtype=np.float64)
    va = a.reshape(-1)
    vb = b.reshape(-1)
    na = np.linalg.norm(va)
    nb = np.linalg.norm(vb)
    if na == 0.0 or nb == 0.0:
        return 0.0
    return float(np.dot(va, vb) / (na * nb))
