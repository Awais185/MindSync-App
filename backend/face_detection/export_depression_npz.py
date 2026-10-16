"""
Export depression MLP weights from the joblib bundle to ``depression_inference_weights.npz``.

Run from backend/:  PYTHONPATH=. python face_detection/export_depression_npz.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

JOBLIB_PATH = Path("models/Adult depression detection/model/mindsync_depression_au_model.joblib")
OUT_PATH = Path("models/Adult depression detection/model/depression_inference_weights.npz")
N_FEATURES = 35
HIDDEN = (64, 32)
N_CLASSES = 4
DTYPE = np.float32


def _find_block(
    data: bytes,
    size: int,
    start: int,
    end: int,
    *,
    max_abs: float = 100.0,
) -> tuple[int, np.ndarray] | None:
    need = size * DTYPE().itemsize
    pos = start
    while pos + need <= end:
        arr = np.frombuffer(data[pos : pos + need], dtype=DTYPE)
        if np.isfinite(arr).all() and float(np.abs(arr).max()) <= max_abs:
            return pos, arr.copy()
        pos += 1
    return None


def _validate_forward(
    mean_: np.ndarray,
    scale_: np.ndarray,
    coefs_0: np.ndarray,
    intercepts_0: np.ndarray,
    coefs_1: np.ndarray,
    intercepts_1: np.ndarray,
    coefs_2: np.ndarray,
    intercepts_2: np.ndarray,
) -> bool:
    rng = np.random.default_rng(0)
    X = rng.normal(size=(16, N_FEATURES)).astype(np.float64)
    mean = mean_.astype(np.float64)
    scale = scale_.astype(np.float64)
    scale_safe = np.where(scale == 0, 1.0, scale)
    Xs = (X - mean) / scale_safe
    c0, i0, c1, i1, c2, i2 = [
        a.astype(np.float64)
        for a in (coefs_0, intercepts_0, coefs_1, intercepts_1, coefs_2, intercepts_2)
    ]
    h = np.maximum(Xs @ c0.T + i0, 0)
    h = np.maximum(h @ c1.T + i1, 0)
    logits = h @ c2.T + i2
    if not np.isfinite(logits).all():
        return False
    exp = np.exp(logits - logits.max(axis=1, keepdims=True))
    p = exp / exp.sum(axis=1, keepdims=True)
    return bool(np.isfinite(p).all() and np.allclose(p.sum(axis=1), 1.0, atol=1e-3))


def main() -> None:
    data = JOBLIB_PATH.read_bytes()
    mean_pos = data.find(b"mean_")
    scale_pos = data.find(b"scale_")
    coef_pos = data.find(b"coefs_")
    intercept_pos = data.find(b"intercepts_")
    if min(mean_pos, scale_pos, coef_pos, intercept_pos) < 0:
        raise SystemExit("Could not locate weight markers in joblib file.")

    def _find_f64_block(start: int, end: int) -> np.ndarray:
        need = N_FEATURES * 8
        for pos in range(start, end):
            arr = np.frombuffer(data[pos : pos + need], dtype=np.float64)
            if np.isfinite(arr).all() and 0.0 <= float(arr.min()) and float(arr.max()) <= 6.0:
                return arr.copy()
        raise ValueError("block not found")

    mean_ = _find_f64_block(mean_pos, scale_pos + 800)
    scale_ = _find_f64_block(scale_pos, coef_pos)

    best = None
    pos = coef_pos
    while pos < intercept_pos:
        c0 = _find_block(data, HIDDEN[0] * N_FEATURES, pos, intercept_pos)
        if not c0:
            break
        pos = c0[0] + HIDDEN[0] * N_FEATURES * DTYPE().itemsize
        i0 = _find_block(data, HIDDEN[0], pos, intercept_pos)
        if not i0:
            pos = c0[0] + 4
            continue
        pos = i0[0] + HIDDEN[0] * DTYPE().itemsize
        c1 = _find_block(data, HIDDEN[1] * HIDDEN[0], pos, intercept_pos)
        if not c1:
            pos = c0[0] + 4
            continue
        pos = c1[0] + HIDDEN[1] * HIDDEN[0] * DTYPE().itemsize
        i1 = _find_block(data, HIDDEN[1], pos, intercept_pos)
        if not i1:
            pos = c0[0] + 4
            continue
        pos = i1[0] + HIDDEN[1] * DTYPE().itemsize
        c2 = _find_block(data, N_CLASSES * HIDDEN[1], pos, intercept_pos + 8000)
        if not c2:
            pos = c0[0] + 4
            continue
        pos = c2[0] + N_CLASSES * HIDDEN[1] * DTYPE().itemsize
        i2 = _find_block(data, N_CLASSES, pos, intercept_pos + 8000)
        if not i2:
            pos = c0[0] + 4
            continue

        coefs_0 = c0[1].reshape(HIDDEN[0], N_FEATURES)
        coefs_1 = c1[1].reshape(HIDDEN[1], HIDDEN[0])
        coefs_2 = c2[1].reshape(N_CLASSES, HIDDEN[1])
        if _validate_forward(
            mean_, scale_, coefs_0, i0[1], coefs_1, i1[1], coefs_2, i2[1]
        ):
            best = (coefs_0, i0[1], coefs_1, i1[1], coefs_2, i2[1])
            break
        pos = c0[0] + 4

    if not best:
        raise SystemExit("Could not locate validated MLP weight blocks in joblib.")

    coefs_0, intercepts_0, coefs_1, intercepts_1, coefs_2, intercepts_2 = best

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        OUT_PATH,
        mean_=mean_,
        scale_=scale_,
        coefs_0=coefs_0.astype(np.float32),
        coefs_1=coefs_1.astype(np.float32),
        coefs_2=coefs_2.astype(np.float32),
        intercepts_0=intercepts_0.astype(np.float32),
        intercepts_1=intercepts_1.astype(np.float32),
        intercepts_2=intercepts_2.astype(np.float32),
        classes_=np.array([0, 1, 2, 3], dtype=np.int64),
        features=np.array(
            [
                "AU01_r",
                "AU02_r",
                "AU04_r",
                "AU05_r",
                "AU06_r",
                "AU07_r",
                "AU09_r",
                "AU10_r",
                "AU12_r",
                "AU14_r",
                "AU15_r",
                "AU17_r",
                "AU20_r",
                "AU23_r",
                "AU25_r",
                "AU26_r",
                "AU45_r",
                "AU01_c",
                "AU02_c",
                "AU04_c",
                "AU05_c",
                "AU06_c",
                "AU07_c",
                "AU09_c",
                "AU10_c",
                "AU12_c",
                "AU14_c",
                "AU15_c",
                "AU17_c",
                "AU20_c",
                "AU23_c",
                "AU25_c",
                "AU26_c",
                "AU28_c",
                "AU45_c",
            ],
            dtype=object,
        ),
    )
    print("Wrote", OUT_PATH, "validated forward pass OK")


if __name__ == "__main__":
    main()
