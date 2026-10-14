"""Run chat mood models on matched face captures and persist results."""

from __future__ import annotations

import logging
import os
from datetime import timedelta
from typing import Any

from django.core.files.base import ContentFile
from django.utils import timezone

from .models import FaceMoodScan

MOOD_SCAN_COOLDOWN = timedelta(minutes=5)

logger = logging.getLogger(__name__)


def mood_success_message(mood: dict[str, Any], modality: str) -> str:
    """Human-readable confirmation after mood is saved."""
    pred = (
        mood.get("prediction")
        or mood.get("dominant_emotion")
        or mood.get("emotion")
        or mood.get("label")
    )
    if not pred and isinstance(mood.get("emotions"), dict):
        em = mood["emotions"]
        if em:
            pred = max(em, key=lambda k: float(em[k] or 0))
    pred_str = str(pred or "analyzed").replace("_", " ").strip().title()
    conf = mood.get("confidence")
    if conf is not None:
        try:
            pct = float(conf)
            if pct <= 1.0:
                pct *= 100.0
            conf_part = f" ({pct:.0f}% confidence)"
        except (TypeError, ValueError):
            conf_part = ""
    else:
        conf_part = ""
    if modality == FaceMoodScan.MODALITY_VIDEO:
        return f"10s video captured and mood saved: {pred_str}{conf_part}"
    return f"Photo captured and mood saved: {pred_str}{conf_part}"


def analyze_image_bytes(image_bytes: bytes, filename: str = "capture.jpg") -> dict[str, Any]:
    from django.core.files.uploadedfile import SimpleUploadedFile

    from chat.models import analyze_uploaded_image_file

    uploaded = SimpleUploadedFile(filename, image_bytes, content_type="image/jpeg")
    prediction, confidence = analyze_uploaded_image_file(uploaded)
    return {
        "status": "success",
        "modality": FaceMoodScan.MODALITY_IMAGE,
        "prediction": prediction,
        "confidence": round(float(confidence), 4),
    }


def analyze_video_path(video_path: str) -> dict[str, Any]:
    from chat.video_model import analyze_video_file_path

    result = analyze_video_file_path(video_path)
    payload = dict(result) if isinstance(result, dict) else {"raw": result}
    payload["status"] = payload.get("status") or "success"
    payload["modality"] = FaceMoodScan.MODALITY_VIDEO
    return payload


def save_face_mood_scan(
    user,
    *,
    mood: dict[str, Any],
    modality: str,
    matched: bool,
    image_bytes: bytes | None = None,
    video_path: str | None = None,
    source: str = "verify_track",
) -> FaceMoodScan:
    row = FaceMoodScan(
        user=user,
        mood=mood,
        modality=modality,
        matched=matched,
        source=source,
    )
    if image_bytes:
        row.capture_image.save(
            f"mood_{user.id}_{modality}.jpg",
            ContentFile(image_bytes),
            save=False,
        )
    if video_path and os.path.exists(video_path):
        with open(video_path, "rb") as fh:
            ext = os.path.splitext(video_path)[1].lower() or ".mp4"
            row.capture_video.save(
                f"mood_{user.id}_{modality}{ext}",
                ContentFile(fh.read()),
                save=False,
            )
    row.save()
    try:
        from users.services.mood_weekly_service import on_mood_scan_saved

        on_mood_scan_saved(user)
    except Exception:
        logger.exception('Mood window hook failed for user %s', user.id)
    logger.info(
        "Face mood saved user:%s scan_id:%s modality:%s matched:%s prediction:%s",
        user.id,
        row.id,
        modality,
        matched,
        mood.get("prediction") or mood.get("dominant_emotion") or mood.get("status"),
    )
    return row


def mood_scan_cooldown_remaining_seconds(user) -> int:
    """Seconds until another image/video mood scan is allowed."""
    last = (
        FaceMoodScan.objects.filter(user=user, matched=True)
        .order_by("-created_at")
        .first()
    )
    if not last:
        return 0
    remaining = MOOD_SCAN_COOLDOWN - (timezone.now() - last.created_at)
    return max(0, int(remaining.total_seconds()))


def is_mood_scan_cooldown_active(user) -> bool:
    return mood_scan_cooldown_remaining_seconds(user) > 0


def mood_cooldown_skip_payload(user) -> dict[str, Any]:
    secs = mood_scan_cooldown_remaining_seconds(user)
    return {
        "skipped": True,
        "reason": "cooldown",
        "cooldown_seconds_remaining": secs,
        "message": (
            f"Mood capture paused — next scan in {max(1, (secs + 59) // 60)} min "
            "(saves data after your last match)."
        ),
    }


def _enrich_mood_response(mood: dict[str, Any], row: FaceMoodScan) -> dict[str, Any]:
    out = dict(mood)
    out["saved"] = True
    out["mood_scan_id"] = row.id
    out["message"] = mood_success_message(mood, row.modality)
    return out


def run_image_mood_on_match(user, image_bytes: bytes, source: str = "verify_track") -> dict[str, Any] | None:
    if is_mood_scan_cooldown_active(user):
        return mood_cooldown_skip_payload(user)
    try:
        mood = analyze_image_bytes(image_bytes)
        row = save_face_mood_scan(
            user,
            mood=mood,
            modality=FaceMoodScan.MODALITY_IMAGE,
            matched=True,
            image_bytes=image_bytes,
            source=source,
        )
        return _enrich_mood_response(mood, row)
    except Exception as exc:
        logger.exception("Image mood on match failed for user %s: %s", user.id, exc)
        return None


def run_video_mood_on_match(user, video_path: str, source: str = "expression_upload") -> dict[str, Any] | None:
    if is_mood_scan_cooldown_active(user):
        return mood_cooldown_skip_payload(user)
    try:
        mood = analyze_video_path(video_path)
        row = save_face_mood_scan(
            user,
            mood=mood,
            modality=FaceMoodScan.MODALITY_VIDEO,
            matched=True,
            video_path=video_path,
            source=source,
        )
        return _enrich_mood_response(mood, row)
    except Exception as exc:
        logger.exception("Video mood on match failed for user %s: %s", user.id, exc)
        return None
