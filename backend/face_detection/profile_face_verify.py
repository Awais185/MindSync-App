"""Verify a probe image against the authenticated user's enrolled face."""

from __future__ import annotations

import os
from typing import Any

from users.models import UserProfile

from .face_verification_service import (
    DEFAULT_THRESHOLD,
    MIN_MATCH_THRESHOLD,
    ensure_profile_embedding,
    verify_face_pair,
)


def _read_enrolled_bytes(profile: UserProfile) -> bytes:
    with profile.face_image.open("rb") as enrolled:
        return enrolled.read()


def verify_probe_for_profile(
    profile: UserProfile,
    probe_bytes: bytes,
    *,
    threshold: float | None = None,
    unlock_capture: bool = False,
) -> dict[str, Any]:
    """
    Compare probe to this profile's enrolled face image (never another user).
    """
    if not profile.face_image:
        return {
            "matched": False,
            "match": False,
            "probability": 0.0,
            "score": 0.0,
            "distance": 1.0,
            "threshold": float(threshold or DEFAULT_THRESHOLD),
            "status": "not_enrolled",
            "error": "Face not enrolled",
        }

    enrolled_bytes = _read_enrolled_bytes(profile)
    ensure_profile_embedding(profile)

    raw_thr = threshold
    if raw_thr is None:
        raw_thr = os.environ.get(
            "FACE_VERIFY_TRACK_THRESHOLD",
            os.environ.get("FACE_MATCH_THRESHOLD", str(DEFAULT_THRESHOLD)),
        )
    try:
        thr = float(raw_thr)
    except (TypeError, ValueError):
        thr = DEFAULT_THRESHOLD
    thr = max(MIN_MATCH_THRESHOLD, min(0.98, thr))

    return verify_face_pair(
        probe_bytes=probe_bytes,
        enrolled_bytes=enrolled_bytes,
        enrolled_embedding=profile.face_embedding or None,
        threshold=thr,
        unlock_capture=unlock_capture,
    )


def verify_probe_for_user(
    user,
    probe_bytes: bytes,
    *,
    threshold: float | None = None,
    unlock_capture: bool = False,
) -> tuple[UserProfile | None, dict[str, Any]]:
    try:
        profile = UserProfile.objects.select_related("user").get(user=user)
    except UserProfile.DoesNotExist:
        return None, {
            "matched": False,
            "match": False,
            "probability": 0.0,
            "score": 0.0,
            "distance": 1.0,
            "threshold": float(threshold or DEFAULT_THRESHOLD),
            "status": "no_profile",
            "error": "Profile not found",
        }
    result = verify_probe_for_profile(
        profile,
        probe_bytes,
        threshold=threshold,
        unlock_capture=unlock_capture,
    )
    return profile, result
