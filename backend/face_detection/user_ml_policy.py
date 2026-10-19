"""When to run adult emotion / depression models (background only)."""

from __future__ import annotations

from django.contrib.auth.models import User

# Matches Flutter signup / profile age range labels.
_CHILD_AGE_RANGE = "4 - 15 years"
_ADULT_AGE_RANGES = frozenset(
    {
        "16 - 30 years",
        "30+ years",
    }
)


def user_allows_adult_ml(user: User | None) -> bool:
    """
    Background emotion + depression ML runs only for users older than 16.

    OpenFace AU extraction is unchanged for all ages.
    """
    if user is None:
        return False
    profile = getattr(user, "profile", None)
    if profile is None:
        return False
    age_range = (getattr(profile, "age_range", None) or "").strip()
    if age_range == _CHILD_AGE_RANGE:
        return False
    if age_range in _ADULT_AGE_RANGES:
        return True
    # Empty or unknown age range: allow unlock mood scans (legacy signups); only 4–15 is blocked.
    if not age_range:
        return True
    return False
