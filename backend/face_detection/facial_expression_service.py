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
from .openface_pipeline import is_openface_available, run_openface_and_analyze
from .user_ml_policy import user_allows_adult_ml
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

    prior_score = capture.face_match_score
    if prior_score is not None and prior_score >= BACKGROUND_FACE_MATCH_THRESHOLD:
        score = float(prior_score)
        matched = True
    else:
        score, matched = face_match_score_from_video_path_multi(
            capture.user,
            capture.video.path,
            threshold=BACKGROUND_FACE_MATCH_THRESHOLD,
            max_frames=6,
            unlock_capture=True,
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

    allow_ml = user_allows_adult_ml(capture.user)

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
                use_depression_model=allow_ml,
            )
        else:
            analysis = run_cross_platform_video_analysis(
                video_path,
                fast_mode=False,
                include_tracked_video=False,
            )
        scores = dict(analysis.scores) if isinstance(analysis.scores, dict) else {}

        mood = capture.mood if isinstance(capture.mood, dict) else None
        if allow_ml and not mood:
            try:
                from .adult_emotion_inference import predict_video_path

                mood = predict_video_path(
                    capture.video.path,
                    max_frames=4,
                    sample_fps=0.15,
                )
            except Exception:
                logger.exception("Emotion ensemble failed for capture %s", capture_id)

        capture.mood = mood or {}
        capture.au_results = {
            **scores,
            "au_summary": analysis.au_summary,
            "face_visibility_ratio": analysis.face_visibility_ratio,
            "behavioral_insights": analysis.behavioral_insights,
            "recommendations": analysis.recommendations,
            "peak_timestamps": analysis.peak_timestamps,
            "adult_ml_applied": allow_ml,
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
                "mood",
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
        if allow_ml:
            try:
                from .mental_health_session import update_daily_session_metrics
                from .models import MentalHealthResult

                mood_label = ""
                if isinstance(capture.mood, dict):
                    mood_label = str(
                        capture.mood.get("prediction")
                        or capture.mood.get("class")
                        or ""
                    )
                MentalHealthResult.objects.create(
                    user=capture.user,
                    stress_score=capture.stress_score,
                    anxiety_score=capture.anxiety_score,
                    depression_score=capture.depression_score,
                    mood=mood_label[:64],
                    dominant_state=capture.dominant_state or "neutral",
                    source_type=MentalHealthResult.SOURCE_RANDOM_USAGE,
                    scan_type=MentalHealthResult.SCAN_UPLOADED,
                    reaction_app_name=capture.source_app_name or "",
                    reaction_package_name=capture.source_package_name or "",
                    openface_summary={
                        "capture_id": capture.id,
                        "active_aus": capture.active_aus or [],
                        "au_results": capture.au_results or {},
                    },
                )
                update_daily_session_metrics(
                    capture.user,
                    mood_label=mood_label or capture.dominant_state,
                    stress=capture.stress_score,
                    anxiety=capture.anxiety_score,
                    depression=capture.depression_score,
                )
            except Exception:
                logger.exception(
                    "MentalHealthResult row failed for facial expression %s", capture_id
                )

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
