"""OpenFace AU processing for [FacialExpressionCapture] rows."""

from __future__ import annotations

import logging
import os
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from datetime import timedelta
from typing import Any

from django.db import close_old_connections
from django.utils import timezone

from .identity import (
    BACKGROUND_FACE_MATCH_THRESHOLD,
    face_match_score_from_video_path_multi,
)
from .json_safe import json_safe_payload
from .models import FacialExpressionCapture
from .openface_pipeline import is_openface_available, run_openface_and_analyze
from .user_ml_policy import user_allows_adult_ml
from .video_au_tracker import run_cross_platform_video_analysis

logger = logging.getLogger(__name__)

_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="facial-expr")

# Background 30s clips only — manual / ephemeral scans must not create DB rows.
BACKGROUND_SOURCE_TYPES = frozenset(
    {
        FacialExpressionCapture.SOURCE_SCHEDULED,
        FacialExpressionCapture.SOURCE_VIDEO_WATCH,
        FacialExpressionCapture.SOURCE_SOCIAL,
    }
)

_STALE_PROCESSING_MINUTES = int(os.environ.get("FACIAL_EXPR_STALE_MINUTES", "25"))
_ANALYSIS_TIMEOUT_SEC = int(os.environ.get("FACIAL_EXPR_ANALYSIS_TIMEOUT_SEC", "480"))
_EMOTION_MAX_FRAMES = int(os.environ.get("FACIAL_EXPR_EMOTION_FRAMES", "8"))


def _au_results_is_placeholder(au_results) -> bool:
    if not isinstance(au_results, dict) or not au_results:
        return True
    keys = set(au_results.keys())
    if keys <= {"capture_meta"}:
        return True
    return False


def capture_needs_processing(capture: FacialExpressionCapture) -> bool:
    if capture.status in (
        FacialExpressionCapture.STATUS_PENDING,
        FacialExpressionCapture.STATUS_FAILED,
        FacialExpressionCapture.STATUS_PROCESSING,
    ):
        return True
    if not (capture.emotion or "").strip():
        return True
    if _au_results_is_placeholder(capture.au_results):
        return True
    return False


def incomplete_facial_expression_queryset():
    from django.db.models import Q

    return (
        FacialExpressionCapture.objects.filter(
            Q(status=FacialExpressionCapture.STATUS_PENDING)
            | Q(status=FacialExpressionCapture.STATUS_FAILED)
            | Q(status=FacialExpressionCapture.STATUS_PROCESSING)
            | Q(emotion="")
            | Q(au_results__isnull=True)
        )
        .exclude(video="")
    )


def _db_json_dict(obj: Any) -> dict:
    """Postgres JSON columns reject NaN/Inf; normalize before save."""
    if not isinstance(obj, dict):
        return {}
    safe = json_safe_payload(obj)
    return safe if isinstance(safe, dict) else {}


def _emotion_label_from_mood(mood: dict | None) -> str:
    if not isinstance(mood, dict):
        return ""
    return str(
        mood.get("prediction") or mood.get("class") or mood.get("dominant") or ""
    ).strip()[:64]


def _run_emotion_model(video_path: str) -> dict:
    from .adult_emotion_inference import predict_video_path

    # ~7–8 frames across a 30s background clip
    raw = predict_video_path(
        video_path,
        max_frames=max(4, _EMOTION_MAX_FRAMES),
        sample_fps=3.5,
    )
    return _db_json_dict(raw) if isinstance(raw, dict) else {}


def reset_stale_processing_captures() -> int:
    """Re-queue captures stuck in processing (worker crash / OpenFace hang)."""
    cutoff = timezone.now() - timedelta(minutes=max(5, _STALE_PROCESSING_MINUTES))
    qs = FacialExpressionCapture.objects.filter(
        status=FacialExpressionCapture.STATUS_PROCESSING,
        updated_at__lt=cutoff,
        processed_at__isnull=True,
    )
    count = qs.count()
    if count:
        qs.update(
            status=FacialExpressionCapture.STATUS_PENDING,
            processing_error="stale_processing_reset",
        )
        logger.warning("Reset %s stale facial expression capture(s) to pending", count)
    return count


def _persist_mental_health_result(capture: FacialExpressionCapture) -> None:
    """Only background scheduled / usage captures update session tables — not manual scans."""
    if capture.source_type not in BACKGROUND_SOURCE_TYPES:
        return
    try:
        from .mental_health_session import update_daily_session_metrics
        from .models import MentalHealthResult

        MentalHealthResult.objects.create(
            user=capture.user,
            stress_score=capture.stress_score,
            anxiety_score=0,
            depression_score=capture.depression_score,
            mood=capture.emotion[:64],
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
            mood_label=capture.emotion or capture.dominant_state,
            emotion=capture.emotion,
            stress=capture.stress_score,
            depression=capture.depression_score,
        )
    except Exception:
        logger.exception(
            "MentalHealthResult row failed for facial expression %s", capture.id
        )


def _run_heavy_analysis(
    video_path: str,
    *,
    clip_cap: float,
    allow_ml: bool,
):
    if is_openface_available():
        return run_openface_and_analyze(
            input_video_path=video_path,
            max_peak_frames=3,
            include_tracked_video=False,
            fast_mode=True,
            max_video_seconds=clip_cap,
            prefer_reencode=True,
            use_depression_model=allow_ml,
        )
    return run_cross_platform_video_analysis(
        video_path,
        fast_mode=True,
        include_tracked_video=False,
        budget_mode=True,
    )


def _apply_emotion_mh_scores(scores: dict, mood_label: str, allow_ml: bool) -> dict:
    if not allow_ml or not mood_label:
        return scores
    from .adult_emotion_inference import mental_health_scores_from_emotion

    stress, _anx, depression = mental_health_scores_from_emotion(mood_label)
    out = dict(scores)
    if not int(out.get("stress_score") or 0):
        out["stress_score"] = stress
    if not int(out.get("depression_score") or 0):
        out["depression_score"] = depression
    dom = mood_label.strip().lower()
    if dom and (out.get("dominant_state") in (None, "", "neutral")):
        out["dominant_state"] = dom[:32]
    return out


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

    if not capture_needs_processing(capture):
        return True

    if capture.status == FacialExpressionCapture.STATUS_PROCESSING:
        age_sec = (timezone.now() - capture.updated_at).total_seconds()
        if age_sec < 120 and not (capture.emotion or "").strip():
            logger.info(
                "Facial expression %s already processing (%.0fs); skip duplicate worker",
                capture_id,
                age_sec,
            )
            return False

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
    video_path = capture.video.path
    clip_cap = float(capture.duration_seconds or 20) + 10.0

    try:
        mood = capture.mood if isinstance(capture.mood, dict) else None
        if not _emotion_label_from_mood(mood):
            try:
                mood = _run_emotion_model(video_path)
            except Exception:
                logger.exception("Emotion ensemble failed for capture %s", capture_id)
                mood = mood or {}

        mood_label_early = _emotion_label_from_mood(mood)
        if mood_label_early:
            capture.mood = _db_json_dict(mood)
            capture.emotion = mood_label_early[:64]
            capture.dominant_state = mood_label_early.lower()[:32]
            capture.save(
                update_fields=["mood", "emotion", "dominant_state", "updated_at"]
            )

        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(
                _run_heavy_analysis,
                video_path,
                clip_cap=clip_cap,
                allow_ml=allow_ml,
            )
            try:
                analysis = future.result(timeout=max(60, _ANALYSIS_TIMEOUT_SEC))
            except FuturesTimeoutError:
                raise RuntimeError(
                    f"analysis_timeout_{_ANALYSIS_TIMEOUT_SEC}s"
                ) from None

        scores = dict(analysis.scores) if isinstance(analysis.scores, dict) else {}
        mood_label = _emotion_label_from_mood(mood) or mood_label_early
        scores = _apply_emotion_mh_scores(scores, mood_label, allow_ml)

        capture.mood = _db_json_dict(mood)
        capture.au_results = _db_json_dict(
            {
                **scores,
                "au_summary": analysis.au_summary,
                "face_visibility_ratio": analysis.face_visibility_ratio,
                "behavioral_insights": analysis.behavioral_insights,
                "recommendations": analysis.recommendations,
                "peak_timestamps": analysis.peak_timestamps,
                "adult_ml_applied": allow_ml,
            }
        )
        capture.dominant_state = str(scores.get("dominant_state") or "neutral")[:32]
        capture.stress_score = int(scores.get("stress_score") or 0)
        capture.depression_score = int(scores.get("depression_score") or 0)
        final_mood = _emotion_label_from_mood(capture.mood) or mood_label
        if final_mood:
            capture.dominant_state = final_mood.lower()[:32]
        capture.emotion = final_mood or (capture.dominant_state or "neutral")[:64]
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
                "depression_score",
                "emotion",
                "active_aus",
                "status",
                "processing_error",
                "processed_at",
                "updated_at",
            ]
        )
        if allow_ml:
            _persist_mental_health_result(capture)

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


def submit_incomplete_batch_recovery(*, limit: int = 3) -> None:
    """Background: process DB rows that have video but no emotion results yet."""
    reset_stale_processing_captures()
    _EXECUTOR.submit(
        process_random_incomplete_batch,
        limit=max(1, limit),
        random_order=False,
    )


def process_random_incomplete_batch(*, limit: int = 5, random_order: bool = True) -> int:
    """
    Find captures with video but missing emotion / AU results; run processing on each.
    Returns number successfully processed.
    """
    reset_stale_processing_captures()
    qs = incomplete_facial_expression_queryset()

    if random_order:
        qs = qs.order_by("?")
    else:
        qs = qs.order_by("created_at")

    processed = 0
    for row in qs[: max(1, limit)]:
        if process_facial_expression_capture_sync(row.id):
            processed += 1
    return processed


def process_all_incomplete_facial_captures(*, limit: int | None = None) -> dict[str, int]:
    """Process every row that still needs emotion/AU results (for management command / recovery)."""
    qs = incomplete_facial_expression_queryset().order_by("created_at")
    total = qs.count()
    if limit is not None:
        qs = qs[: max(1, int(limit))]
    done = 0
    for row in qs.iterator(chunk_size=20):
        close_old_connections()
        if process_facial_expression_capture_sync(row.id):
            done += 1
    remaining = incomplete_facial_expression_queryset().count()
    return {"processed": done, "total_candidates": total, "remaining": remaining}
