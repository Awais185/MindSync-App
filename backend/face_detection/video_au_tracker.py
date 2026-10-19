"""
Cross-platform face behavior video analysis (macOS/Linux/Windows without OpenFace).

Samples frames, maps emotion signals to FACS-style AU intensities, runs the same
:mod:`au_emotion_pipeline` scoring as OpenFace CSV, and renders an annotated MP4.
"""

from __future__ import annotations

import logging
import os
import tempfile
import uuid
from collections import Counter
from typing import Any

import cv2
import numpy as np

from .au_emotion_pipeline import STATE_AUS
from .emotion_models import predict_image_pil
from .face_mesh_au import (
    close_face_mesh,
    draw_mesh_on_bgr,
    mediapipe_available,
    merge_au_dicts,
    process_bgr_frame,
)
from .openface_pipeline import (
    OpenFaceAnalysisResult,
    _transcode_to_h264_aac_mp4,
    open_cv_video_writer,
)

logger = logging.getLogger(__name__)

# Emotion label → indicative AU intensities (0–1 scale before confidence scaling).
_EMOTION_AU_PROFILES: dict[str, dict[str, float]] = {
    "angry": {"AU04": 0.85, "AU07": 0.7, "AU23": 0.65, "AU10": 0.45, "AU14": 0.4},
    "anger": {"AU04": 0.85, "AU07": 0.7, "AU23": 0.65, "AU10": 0.45},
    "disgust": {"AU09": 0.8, "AU10": 0.75, "AU04": 0.35, "AU17": 0.3},
    "fear": {"AU01": 0.7, "AU02": 0.75, "AU04": 0.5, "AU05": 0.65, "AU20": 0.55, "AU25": 0.4},
    "fearful": {"AU01": 0.7, "AU02": 0.75, "AU05": 0.65, "AU20": 0.55},
    "sad": {"AU01": 0.45, "AU04": 0.55, "AU15": 0.9, "AU17": 0.5, "AU06": 0.25},
    "sadness": {"AU01": 0.45, "AU15": 0.9, "AU17": 0.5, "AU04": 0.5},
    "surprise": {"AU01": 0.8, "AU02": 0.8, "AU05": 0.7, "AU26": 0.65, "AU25": 0.5},
    "happy": {"AU06": 0.85, "AU12": 0.9, "AU14": 0.35},
    "happiness": {"AU06": 0.85, "AU12": 0.9},
    "neutral": {"AU06": 0.2, "AU12": 0.15, "AU01": 0.1},
}


def _normalize_emotion_key(label: str) -> str:
    return (label or "neutral").strip().lower().replace(" ", "_")


def emotion_to_au_intensities(label: str, confidence: float) -> dict[str, float]:
    key = _normalize_emotion_key(label)
    profile = _EMOTION_AU_PROFILES.get(key) or _EMOTION_AU_PROFILES["neutral"]
    conf = max(0.2, min(1.0, float(confidence or 0.5)))
    return {au: float(v) * conf for au, v in profile.items() if v > 0}


def _cross_platform_model_scores(
    emotion_label: str,
    face_visibility_ratio: float,
    *,
    analysis_source: str,
) -> dict[str, Any]:
    """Cross-platform path: emotion model only (no heuristic AU stress/anxiety/depression)."""
    label = (emotion_label or "").strip()
    dominant = label.lower() if label else "neutral"
    recs: list[str] = []
    if label:
        recs.append(
            f"Your adult emotion model read «{label}» across sampled frames — use this as the primary signal."
        )
        if dominant in {"sad", "sadness", "fear", "fearful", "angry", "anger"}:
            recs.append("Take a short break, breathe slowly, and check in with how you feel.")
        elif dominant in {"happy", "happiness", "neutral"}:
            recs.append("Expressions look steady — keep balanced screen-time breaks through the day.")
    else:
        recs.append(
            "Not enough clear face frames for the emotion model. Retry with front lighting and your face centered."
        )
    return {
        "stress_score": 0,
        "anxiety_score": 0,
        "depression_score": 0,
        "dominant_state": dominant,
        "dominant_states": [dominant] if dominant != "neutral" else [],
        "max_score": 0,
        "active_aus": [],
        "au_disease_table": dict(STATE_AUS),
        "matched_aus_by_state": {},
        "state_probabilities": {},
        "face_visibility_ratio": float(face_visibility_ratio),
        "au_summary": [],
        "recommendations": recs,
        "behavioral_insights": [],
        "analysis_source": analysis_source,
        "emotion_label": label,
    }


def _legacy_scores_from_analyze_frame(
    frame: dict[str, Any],
    *,
    analysis_source: str = "au_video_tracker",
) -> dict[str, Any]:
    p_stress = float(frame["stress_score"])
    p_anx = float(frame["anxiety_score"])
    p_dep = float(frame["depression_score"])
    stress_i = int(round(p_stress * 100))
    anx_i = int(round(p_anx * 100))
    dep_i = int(round(p_dep * 100))
    dominant = str(frame["dominant_state"])
    return {
        "stress_score": stress_i,
        "anxiety_score": anx_i,
        "depression_score": dep_i,
        "dominant_state": dominant,
        "dominant_states": [dominant] if dominant != "neutral" else [],
        "max_score": max(stress_i, anx_i, dep_i),
        "active_aus": list(frame.get("active_aus") or []),
        "au_disease_table": dict(STATE_AUS),
        "matched_aus_by_state": frame.get("matched_aus_by_state") or {},
        "state_probabilities": frame.get("state_probabilities") or {},
        "face_visibility_ratio": float(frame.get("face_visibility_ratio") or 0.0),
        "au_summary": frame.get("au_summary") or [],
        "recommendations": frame.get("recommendations") or [],
        "behavioral_insights": frame.get("behavioral_insights") or [],
        "analysis_source": analysis_source,
    }


def _detect_face_rect(bgr: np.ndarray) -> tuple[int, int, int, int] | None:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)
    cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    if cascade.empty():
        return None
    faces = cascade.detectMultiScale(
        gray,
        scaleFactor=1.08,
        minNeighbors=6,
        minSize=(64, 64),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )
    if faces is None or len(faces) == 0:
        return None
    x, y, w, h = max(faces, key=lambda f: int(f[2]) * int(f[3]))
    return int(x), int(y), int(w), int(h)


def _predict_emotion_on_face(bgr: np.ndarray, face_rect: tuple[int, int, int, int] | None):
    from PIL import Image

    if face_rect:
        x, y, fw, fh = face_rect
        pad = int(0.08 * max(fw, fh))
        x0 = max(0, x - pad)
        y0 = max(0, y - pad)
        x1 = min(bgr.shape[1], x + fw + pad)
        y1 = min(bgr.shape[0], y + fh + pad)
        crop = bgr[y0:y1, x0:x1]
        if crop.size == 0:
            crop = bgr
    else:
        crop = bgr
    rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    return predict_image_pil(Image.fromarray(rgb))


def _draw_overlay(
    frame: np.ndarray,
    face_rect: tuple[int, int, int, int] | None,
    emotion_label: str,
    frame_aus: dict[str, float],
    scores: dict[str, Any],
    *,
    mesh_mode: bool = False,
) -> np.ndarray:
    """Face box + top score banner; mesh contours drawn before this when enabled."""
    out = frame.copy()
    h, w = out.shape[:2]

    if face_rect:
        x, y, fw, fh = face_rect
        cv2.rectangle(out, (x, y), (x + fw, y + fh), (80, 220, 80), 2)
        cv2.putText(
            out,
            "Face tracked",
            (x, min(y + fh + 22, h - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (80, 220, 80),
            1,
            cv2.LINE_AA,
        )
    else:
        cv2.putText(
            out,
            "No face detected in frame",
            (12, h - 16),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 120, 80),
            1,
            cv2.LINE_AA,
        )

    dom = str(scores.get("dominant_state", "neutral"))
    lines = [
        f"Emotion model: {emotion_label or dom or '—'}",
        "MindSync · tracked preview (scores from models in app summary)",
        (
            "MediaPipe face mesh overlay"
            if mesh_mode
            else "Face tracking overlay"
        ),
    ]
    pad = 8
    line_h = 20
    box_h = line_h * len(lines) + pad * 2
    cv2.rectangle(out, (0, 0), (w, box_h), (0, 0, 0), -1)
    for i, line in enumerate(lines):
        cv2.putText(
            out,
            line,
            (pad, pad + 16 + i * line_h),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.48,
            (255, 255, 255),
            1,
            cv2.LINE_AA,
        )
    return out


def run_cross_platform_video_analysis(
    video_path: str,
    *,
    fast_mode: bool = True,
    include_tracked_video: bool = True,
    budget_mode: bool = False,
) -> OpenFaceAnalysisResult:
    """
    Process a normalized MP4: aggregate AUs from per-frame emotion, score via
    :func:`analyze_frame`, optionally emit H.264 annotated video bytes.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("Could not open video for AU analysis.")

    fps = float(cap.get(cv2.CAP_PROP_FPS) or 24.0)
    fps = max(fps, 1.0)
    if budget_mode:
        sample_every = 5
        max_frames_out = 160
        max_decode_frames = int(min(fps * 32, 400))
    else:
        sample_every = 3 if fast_mode else 2
        max_frames_out = 450 if fast_mode else 900
        max_decode_frames = 10_000
    video_stride = 2 if budget_mode else 1

    emotion_votes: Counter[str] = Counter()
    peak_candidates: list[tuple[float, float]] = []
    writer: cv2.VideoWriter | None = None
    raw_out = ""
    h264_out = ""
    out_w = 0
    out_h = 0
    frame_idx = 0
    written = 0
    last_frame_aus: dict[str, float] = {}
    last_emotion_label = ""
    last_display_scores: dict[str, Any] = {
        "stress_score": 0,
        "anxiety_score": 0,
        "depression_score": 0,
        "dominant_state": "neutral",
    }
    last_face_rect: tuple[int, int, int, int] | None = None
    last_mesh_landmarks = None
    use_mesh = mediapipe_available()
    mesh_frames = 0
    source_tag = "mediapipe_au_video_tracker" if use_mesh else "au_video_tracker"

    try:
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            if written >= max_frames_out or frame_idx >= max_decode_frames:
                break

            time_sec = frame_idx / fps
            run_model = frame_idx % sample_every == 0
            will_write = include_tracked_video and (frame_idx % video_stride == 0)
            run_mesh = use_mesh and (run_model or will_write)

            mesh_aus: dict[str, float] = {}
            mesh_landmarks = None
            if run_mesh:
                mesh_res = process_bgr_frame(bgr)
                mesh_aus = mesh_res.aus if run_model else {}
                mesh_landmarks = mesh_res.landmarks
                if mesh_res.face_rect is not None:
                    last_face_rect = mesh_res.face_rect
                if mesh_aus:
                    mesh_frames += 1
                if mesh_landmarks is not None:
                    last_mesh_landmarks = mesh_landmarks

            face_rect = (
                _detect_face_rect(bgr) if (run_model and not use_mesh) else None
            )
            if face_rect is not None:
                last_face_rect = face_rect

            if run_model:
                rect_for_model = last_face_rect
                preds = _predict_emotion_on_face(bgr, rect_for_model)
                if preds:
                    top = preds[0]
                    last_emotion_label = str(top["label"])
                    conf = float(top.get("score") or 0.5)
                    if last_emotion_label:
                        emotion_votes[last_emotion_label] += max(conf, 0.1)
                    peak_candidates.append((time_sec, conf))

                last_frame_aus = merge_au_dicts({}, mesh_aus)
                last_display_scores = _cross_platform_model_scores(
                    last_emotion_label,
                    float(mesh_frames) / float(max(frame_idx, 1)),
                    analysis_source=source_tag,
                )

            if will_write:
                if writer is None:
                    fh, fw = bgr.shape[:2]
                    scale = 720 / fw if fw > 720 else 1.0
                    out_w = int(fw * scale)
                    out_h = int(fh * scale)
                    raw_out = os.path.join(
                        tempfile.gettempdir(),
                        f"mindsync_au_track_{uuid.uuid4().hex[:10]}.mp4",
                    )
                    out_fps = min(fps, 20.0) if budget_mode else min(fps, 24.0)
                    writer = open_cv_video_writer(raw_out, out_fps, out_w, out_h)
                    if writer is None or not writer.isOpened():
                        logger.warning("AU tracker: could not open video writer for %s", raw_out)
                        writer = None
                        raw_out = ""
                if writer is not None:
                    canvas = bgr
                    lm = mesh_landmarks if mesh_landmarks is not None else last_mesh_landmarks
                    if lm is not None:
                        canvas = draw_mesh_on_bgr(canvas, lm)
                    overlay_rect = last_face_rect
                    display = _draw_overlay(
                        canvas,
                        overlay_rect,
                        last_emotion_label,
                        last_frame_aus,
                        last_display_scores,
                        mesh_mode=use_mesh and lm is not None,
                    )
                    if display.shape[1] != out_w or display.shape[0] != out_h:
                        display = cv2.resize(display, (out_w, out_h))
                    writer.write(display)
                    written += 1

            frame_idx += 1
    finally:
        cap.release()
        if writer is not None:
            writer.release()
        if use_mesh:
            close_face_mesh()

    dominant_emotion = ""
    if emotion_votes:
        dominant_emotion = emotion_votes.most_common(1)[0][0]
    elif last_emotion_label:
        dominant_emotion = last_emotion_label

    visibility = float(mesh_frames) / float(max(frame_idx, 1)) if frame_idx else 0.0
    if visibility <= 0.0 and emotion_votes:
        visibility = min(1.0, len(emotion_votes) / 12.0)

    if not dominant_emotion and frame_idx > 0:
        logger.warning("AU video tracker: no emotion model signal in clip")

    scores = _cross_platform_model_scores(
        dominant_emotion,
        visibility,
        analysis_source=source_tag,
    )
    peak_candidates.sort(key=lambda x: x[1], reverse=True)
    peak_timestamps = [t for t, _ in peak_candidates[:3]]

    tracked_bytes: bytes | None = None
    tracked_ext = ".mp4"
    if include_tracked_video and raw_out and os.path.isfile(raw_out):
        h264_out = os.path.join(
            tempfile.gettempdir(),
            f"mindsync_au_h264_{uuid.uuid4().hex[:10]}.mp4",
        )
        try:
            _transcode_to_h264_aac_mp4(raw_out, h264_out, fast_mode=True)
            if os.path.isfile(h264_out) and os.path.getsize(h264_out) > 4096:
                with open(h264_out, "rb") as f:
                    tracked_bytes = f.read()
        except Exception as exc:
            logger.warning("AU tracked video transcode failed: %s", exc)
            try:
                if os.path.isfile(raw_out) and os.path.getsize(raw_out) > 4096:
                    with open(raw_out, "rb") as f:
                        tracked_bytes = f.read()
            except OSError:
                pass
        finally:
            for p in (raw_out, h264_out):
                try:
                    if p and os.path.isfile(p):
                        os.unlink(p)
                except OSError:
                    pass

    if include_tracked_video and not tracked_bytes:
        logger.warning(
            "AU video tracker: no tracked MP4 produced (written=%s raw=%s)",
            written,
            bool(raw_out),
        )

    logger.info(
        "AU video tracker done frames=%s written=%s mesh_frames=%s emotion=%s visibility=%.2f video=%s",
        frame_idx,
        written,
        mesh_frames,
        dominant_emotion or "—",
        visibility,
        bool(tracked_bytes),
    )

    return OpenFaceAnalysisResult(
        scores=scores,
        peak_timestamps=peak_timestamps,
        face_visibility_ratio=float(scores.get("face_visibility_ratio") or 0.0),
        au_summary=list(scores.get("au_summary") or []),
        behavioral_insights=list(scores.get("behavioral_insights") or []),
        recommendations=list(scores.get("recommendations") or []),
        tracked_video_bytes=tracked_bytes,
        tracked_video_ext=tracked_ext,
    )
