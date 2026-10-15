"""OpenFace AU processing for [FacialExpressionCapture] rows."""

from __future__ import annotations

import logging
import os
import threading
from concurrent.futures import ThreadPoolExecutor

from django.db import close_old_connections
from django.utils import timezone

from .identity import (
    BACKGROUND_FACE_MATCH_THRESHOLD,
    face_match_score_from_video_path_multi,
)
from .models import FacialExpressionCapture
from .emotion_score_fallback import merge_emotion_fallback, openface_results_weak
from .openface_pipeline import is_openface_available, run_openface_and_analyze
from .video_au_tracker import run_cross_platform_video_analysis

logger = logging.getLogger(__name__)

_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="facial-expr")


def _delete_video_file(capture: FacialExpressionCapture) -> None:
    try:
        if capture.video and os.path.exists(capture.video.path):
            os.remove(capture.video.path)
        capture.video = ""
        capture.video_deleted_at = timezone.now()
        capture.save(update_fields=["video", "video_deleted_at", "updated_at"])
    except Exception:
        logger.exception("Failed to delete facial expression video for id=%s", capture.id)


def process_facial_expression_capture_sync(capture_id: int) -> bool:
    """Run OpenFace on stored video and persist AU results. Returns True on success."""
    close_old_connections()
    capture = FacialExpressionCapture.objects.filter(id=capture_id).first()
    if capture is None:
        return False

    if not capture.video or not os.path.exists(capture.video.path):
        capture.status = FacialExpressionCapture.STATUS_FAILED
        capture.processing_error = "video_file_missing"
        capture.processed_at = timezone.now()
        capture.save(update_fields=["status", "processing_error", "processed_at", "updated_at"])
        return False

    if capture.status == FacialExpressionCapture.STATUS_COMPLETED and capture.au_results:
        return True

    # Background 20s clips: verify identity on multiple frames before OpenFace.
    score, matched = face_match_score_from_video_path_multi(
        capture.user,
        capture.video.path,
        threshold=BACKGROUND_FACE_MATCH_THRESHOLD,
        max_frames=6,
    )
    capture.face_match_score = score
    if not matched:
        logger.warning(
            "Background facial expression rejected — user=%s capture=%s score=%.3f (<%.0f%%)",
            capture.user_id,
            capture_id,
            score,
            BACKGROUND_FACE_MATCH_THRESHOLD * 100,
        )
        video_path = capture.video.path if capture.video else None
        capture.delete()
        if video_path and os.path.exists(video_path):
            try:
                os.remove(video_path)
            except OSError:
                logger.exception("Failed to remove rejected facial expression video")
        return False

    capture.status = FacialExpressionCapture.STATUS_PROCESSING
    capture.processing_error = ""
    capture.save(
        update_fields=["face_match_score", "status", "processing_error", "updated_at"]
    )

    try:
        clip_cap = float(capture.duration_seconds or 20) + 10.0
        video_path = capture.video.path
        if is_openface_available():
            analysis = run_openface_and_analyze(
                input_video_path=video_path,
                max_peak_frames=3,
                include_tracked_video=False,
                fast_mode=False,
                max_video_seconds=clip_cap,
                prefer_reencode=True,
            )
        else:
            analysis = run_cross_platform_video_analysis(
                video_path,
                fast_mode=False,
                include_tracked_video=False,
            )
        scores = dict(analysis.scores) if isinstance(analysis.scores, dict) else {}
        if openface_results_weak(scores):
            try:
                from .emotion_models import predict_video_path

                deepface = predict_video_path(capture.video.path, max_frames=10, sample_fps=1.0)
            except Exception:
                deepface = {}
            scores = merge_emotion_fallback(scores, deepface_video=deepface, chat_video=None)
        capture.au_results = {
            **scores,
            "au_summary": analysis.au_summary,
            "face_visibility_ratio": analysis.face_visibility_ratio,
            "behavioral_insights": analysis.behavioral_insights,
            "recommendations": analysis.recommendations,
            "peak_timestamps": analysis.peak_timestamps,
        }
        capture.dominant_state = str(scores.get("dominant_state") or "neutral")[:32]
        capture.stress_score = int(scores.get("stress_score") or 0)
        capture.anxiety_score = int(scores.get("anxiety_score") or 0)
        capture.depression_score = int(scores.get("depression_score") or 0)
        capture.active_aus = list(scores.get("active_aus") or [])
        capture.status = FacialExpressionCapture.STATUS_COMPLETED
        capture.processing_error = ""
        capture.processed_at = timezone.now()
        capture.save(
            update_fields=[
                "au_results",
                "dominant_state",
                "stress_score",
                "anxiety_score",
                "depression_score",
                "active_aus",
                "status",
                "processing_error",
                "processed_at",
                "updated_at",
            ]
        )
        # Keep video file for 12h; cleanup_old_videos removes files and keeps AU rows.
        logger.info("Facial expression capture %s processed successfully", capture_id)
        return True
    except Exception as exc:
        logger.exception("OpenFace failed for facial expression capture %s", capture_id)
        capture.status = FacialExpressionCapture.STATUS_FAILED
        capture.processing_error = str(exc)[:4000]
        capture.processed_at = timezone.now()
        capture.save(
            update_fields=["status", "processing_error", "processed_at", "updated_at"]
        )
        return False
    finally:
        close_old_connections()


def submit_facial_expression_processing(capture_id: int) -> None:
    _EXECUTOR.submit(process_facial_expression_capture_sync, capture_id)


def process_random_incomplete_batch(*, limit: int = 5, random_order: bool = True) -> int:
    """
    Find captures with a video file but no completed AU results; run OpenFace on each.
    Returns number successfully processed.
    """
    from django.db.models import Q

    qs = (
        FacialExpressionCapture.objects.filter(
            Q(status=FacialExpressionCapture.STATUS_PENDING)
            | Q(status=FacialExpressionCapture.STATUS_FAILED)
            | Q(status=FacialExpressionCapture.STATUS_PROCESSING)
            | Q(au_results__isnull=True)
        )
        .exclude(video="")
    )

    if random_order:
        qs = qs.order_by("?")
    else:
        qs = qs.order_by("created_at")

    processed = 0
    for row in qs[: max(1, limit)]:
        if process_facial_expression_capture_sync(row.id):
            processed += 1
    return processed
