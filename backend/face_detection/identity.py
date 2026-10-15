"""Verify enrolled user identity from a video file (single or multi-frame)."""

from __future__ import annotations

import logging
import os

import cv2

from face_detection.face_verification_service import DEFAULT_THRESHOLD, verify_face_pair
from users.models import UserProfile

logger = logging.getLogger(__name__)

BACKGROUND_FACE_MATCH_THRESHOLD = float(
    os.environ.get("BACKGROUND_FACE_MATCH_THRESHOLD", "0.80")
)


def _match_threshold() -> float:
    return float(
        os.environ.get(
            "FACE_VERIFY_TRACK_THRESHOLD",
            os.environ.get("FACE_MATCH_THRESHOLD", str(DEFAULT_THRESHOLD)),
        )
    )


def _score_frame_against_profile(profile: UserProfile, frame) -> float:
    ok_enc, buf = cv2.imencode(".jpg", frame)
    if not ok_enc:
        return 0.0
    uploaded = buf.tobytes()
    with profile.face_image.open("rb") as enrolled_f:
        enrolled_bytes = enrolled_f.read()
    from face_detection.face_verification_service import ensure_profile_embedding

    result = verify_face_pair(
        probe_bytes=uploaded,
        enrolled_bytes=enrolled_bytes,
        enrolled_embedding=ensure_profile_embedding(profile),
        threshold=_match_threshold(),
        unlock_capture=False,
    )
    if result.get("status") == "rejected":
        return 0.0
    return float(result.get("probability") or 0.0)


def face_match_score_from_video_path(
    user,
    video_path: str,
    *,
    threshold: float | None = None,
) -> tuple[float, bool]:
    """Returns (best score 0..1, matched). Uses multiple frames when possible."""
    return face_match_score_from_video_path_multi(
        user,
        video_path,
        threshold=threshold,
        max_frames=1,
    )


def face_match_score_from_video_path_multi(
    user,
    video_path: str,
    *,
    threshold: float | None = None,
    max_frames: int = 6,
) -> tuple[float, bool]:
    """
    Sample frames across the clip; return max similarity vs enrolled face.
    matched when max score >= threshold (default 80% for background monitoring).
    """
    match_thr = threshold if threshold is not None else BACKGROUND_FACE_MATCH_THRESHOLD

    try:
        profile = UserProfile.objects.select_related("user").get(user=user)
    except UserProfile.DoesNotExist:
        return 0.0, False

    if not profile.face_image or not profile.face_enrolled:
        return 0.0, False

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return 0.0, False

    try:
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        sample_count = max(1, min(max_frames, 8))
        indices: list[int] = []
        if frame_count > sample_count:
            step = max(1, frame_count // sample_count)
            indices = [min(i * step, frame_count - 1) for i in range(sample_count)]
        else:
            indices = list(range(sample_count))

        best = 0.0
        frames_read = 0
        for idx in indices:
            if frame_count > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, float(idx))
            ok, frame = cap.read()
            if not ok or frame is None:
                continue
            frames_read += 1
            score = _score_frame_against_profile(profile, frame)
            best = max(best, score)

        if frames_read == 0:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, frame = cap.read()
            if ok and frame is not None:
                best = _score_frame_against_profile(profile, frame)
    finally:
        cap.release()

    matched = best >= match_thr
    logger.info(
        "Face match video user=%s score=%.3f threshold=%.2f matched=%s path=%s",
        user.id,
        best,
        match_thr,
        matched,
        os.path.basename(video_path),
    )
    return best, matched
