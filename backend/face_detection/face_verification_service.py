"""
Production face verification: quality gate → embedding → distance → probability.

Optional DeepFace (Facenet512 + RetinaFace) when installed; OpenCV fallback otherwise.
Match when probability >= threshold (default 0.5).
"""

from __future__ import annotations

import logging
import math
import os
from io import BytesIO
from typing import Any

import numpy as np

from .face_quality_gate import analyze_face_frame
from .image_match import cosine_similarity_face_images

logger = logging.getLogger(__name__)

DEFAULT_THRESHOLD = 0.80
MIN_MATCH_THRESHOLD = 0.80
EMBEDDING_SIZE = 112

_insight_app: Any | None = None
_insight_init_done = False


def _get_insight_app() -> Any | None:
    """Lazy-load InsightFace so API startup works without optional deps."""
    global _insight_app, _insight_init_done
    if _insight_init_done:
        return _insight_app
    _insight_init_done = True
    try:
        # pyrefly: ignore [missing-import]
        from insightface.app import FaceAnalysis

        root = os.environ.get("INSIGHTFACE_MODEL_ROOT", "./model_cache")
        app = FaceAnalysis(
            name=os.environ.get("INSIGHTFACE_MODEL", "buffalo_sc"),
            root=root,
            providers=["CPUExecutionProvider"],
        )
        app.prepare(ctx_id=0, det_size=(320, 320))
        _insight_app = app
        logger.info("InsightFace loaded (model=%s)", os.environ.get("INSIGHTFACE_MODEL", "buffalo_sc"))
    except Exception as exc:
        logger.info(
            "InsightFace not available (%s); using DeepFace/OpenCV embeddings.",
            exc,
        )
        _insight_app = None
    return _insight_app


def distance_to_probability(distance: float) -> float:
    """Sigmoid map: distance < 0.5 → probability > 0.5."""
    return float(1.0 / (1.0 + math.exp(10.0 * (float(distance) - 0.5))))


def euclidean_distance(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=np.float64).reshape(-1)
    b = np.asarray(b, dtype=np.float64).reshape(-1)
    if a.shape != b.shape or a.size == 0:
        return 1.0
    return float(np.linalg.norm(a - b))


def _l2_normalize(vec: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(vec))
    if n <= 1e-9:
        return vec
    return vec / n


def _extract_face_crop_bgr(bgr: np.ndarray) -> np.ndarray | None:
    import cv2

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    if cascade.empty():
        return None
    faces = cascade.detectMultiScale(
        gray, scaleFactor=1.1, minNeighbors=5, minSize=(48, 48)
    )
    if faces is None or len(faces) == 0:
        return None
    x, y, w, h = max(faces, key=lambda f: int(f[2]) * int(f[3]))
    pad = int(0.15 * max(w, h))
    x0 = max(0, x - pad)
    y0 = max(0, y - pad)
    x1 = min(bgr.shape[1], x + w + pad)
    y1 = min(bgr.shape[0], y + h + pad)
    return bgr[y0:y1, x0:x1]


def _embedding_opencv(image_bytes: bytes) -> np.ndarray | None:
    import cv2
    from PIL import Image

    try:
        rgb = np.asarray(Image.open(BytesIO(image_bytes)).convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    except Exception:
        return None
    crop = _extract_face_crop_bgr(bgr)
    if crop is None or crop.size == 0:
        return None
    resized = cv2.resize(crop, (EMBEDDING_SIZE, EMBEDDING_SIZE), interpolation=cv2.INTER_AREA)
    vec = resized.astype(np.float64).reshape(-1) / 255.0
    return _l2_normalize(vec)


def _embedding_deepface(image_bytes: bytes) -> np.ndarray | None:
    if os.environ.get("DEEPFACE_VERIFY", "1").strip().lower() in {"0", "false", "no"}:
        return None
    try:
        # pyrefly: ignore [missing-import]
        from deepface import DeepFace
    except ImportError:
        return None

    import tempfile

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp.write(image_bytes)
            tmp_path = tmp.name
        result = DeepFace.represent(
            img_path=tmp_path,
            model_name=os.environ.get("DEEPFACE_MODEL", "Facenet512"),
            detector_backend=os.environ.get("DEEPFACE_DETECTOR", "opencv"),
            enforce_detection=True,
            align=True,
        )
        if not result:
            return None
        emb = np.asarray(result[0]["embedding"], dtype=np.float64)
        return _l2_normalize(emb)
    except Exception as exc:
        logger.debug("DeepFace embedding skipped: %s", exc)
        return None
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def _embedding_insightface(image_bytes: bytes) -> np.ndarray | None:
    insight_app = _get_insight_app()
    if insight_app is None:
        return None
    try:
        import cv2
        from PIL import Image
        rgb = np.asarray(Image.open(BytesIO(image_bytes)).convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        faces = insight_app.get(bgr)
        if not faces:
            return None
        # Largest face wins
        faces = sorted(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]), reverse=True)
        return faces[0].normed_embedding
    except Exception as exc:
        logger.debug("InsightFace embedding skipped: %s", exc)
        return None


def compute_embedding(image_bytes: bytes) -> np.ndarray | None:
    emb = _embedding_insightface(image_bytes)
    if emb is not None:
        return emb
    emb = _embedding_deepface(image_bytes)
    if emb is not None:
        return emb
    return _embedding_opencv(image_bytes)


def embedding_to_list(emb: np.ndarray) -> list[float]:
    return [float(x) for x in np.asarray(emb, dtype=np.float64).reshape(-1)]


def list_to_embedding(data: list[float] | None) -> np.ndarray | None:
    if not data:
        return None
    try:
        return _l2_normalize(np.asarray(data, dtype=np.float64))
    except Exception:
        return None


def cosine_distance(a: np.ndarray, b: np.ndarray) -> float:
    """Distance in [0, 1] from cosine similarity in [-1, 1]."""
    a = _l2_normalize(np.asarray(a, dtype=np.float64).reshape(-1))
    b = _l2_normalize(np.asarray(b, dtype=np.float64).reshape(-1))
    if a.size == 0 or b.size == 0:
        return 1.0
    sim = float(np.clip(np.dot(a, b), -1.0, 1.0))
    return float((1.0 - sim) / 2.0)


def verify_face_pair(
    *,
    probe_bytes: bytes,
    enrolled_bytes: bytes,
    enrolled_embedding: list[float] | None,
    threshold: float = DEFAULT_THRESHOLD,
    unlock_capture: bool = False,
) -> dict[str, Any]:
    """
    Full pipeline. Returns API dict with matched, probability, distance, threshold.
    """
    threshold = max(MIN_MATCH_THRESHOLD, min(0.98, float(threshold)))

    ok_frame, reject_reason, frame_meta = analyze_face_frame(
        probe_bytes, unlock_capture=unlock_capture
    )
    if not ok_frame:
        reason = (reject_reason or "rejected").lower()
        return {
            "matched": False,
            "match": False,
            "probability": 0.0,
            "score": 0.0,
            "distance": 1.0,
            "threshold": threshold,
            "status": "rejected",
            "reject_reason": reject_reason,
            **frame_meta,
        }

    probe_emb = compute_embedding(probe_bytes)
    # Always derive the reference from the enrolled still image so probe/ref use the same backend.
    ref_emb = compute_embedding(enrolled_bytes)
    if ref_emb is None:
        ref_emb = list_to_embedding(enrolled_embedding)

    if probe_emb is None or ref_emb is None:
        distance = 1.0
        method = "no_face_detected"
    elif probe_emb.shape != ref_emb.shape:
        distance = 1.0
        method = "embedding_dim_mismatch"
        logger.warning(
            "Face embedding dimension mismatch probe=%s ref=%s; treating as no match",
            probe_emb.shape,
            ref_emb.shape,
        )
    else:
        distance = cosine_distance(probe_emb, ref_emb)
        method = "embedding"

    probability = distance_to_probability(distance)
    matched = probability >= threshold

    out: dict[str, Any] = {
        "matched": matched,
        "match": matched,
        "probability": round(probability, 4),
        "score": round(probability, 4),
        "distance": round(distance, 4),
        "threshold": threshold,
        "status": "verified" if matched else "no_match",
        "method": method,
        **frame_meta,
    }
    return out


def ensure_profile_embedding(profile) -> list[float] | None:
    """Compute and persist enrollment embedding; refresh when stale or wrong size."""
    if not profile.face_image:
        return None
    try:
        with profile.face_image.open("rb") as f:
            raw = f.read()
        emb = compute_embedding(raw)
        if emb is None:
            return None
        data = embedding_to_list(emb)
        existing = getattr(profile, "face_embedding", None) or []
        if not existing or len(existing) != len(data):
            profile.face_embedding = data
            profile.save(update_fields=["face_embedding"])
        return data
    except Exception as exc:
        logger.warning("Failed to store face embedding for user %s: %s", profile.user_id, exc)
        return None
