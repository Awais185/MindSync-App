from __future__ import annotations

from collections import Counter
from datetime import timedelta
from typing import Any

from django.db.models import Avg
from django.utils import timezone

from .models import FaceVerificationEvent, ScreenTime
from users.models import ScreenUsageEvent, VideoChunkAnalysis


_SOCIAL_KEYWORDS = (
    "instagram",
    "facebook",
    "youtube",
    "tiktok",
    "trill",
    "musically",
    "snapchat",
)
_WHATSAPP_KEYWORD = "whatsapp"

_VIDEO_KEYWORDS = (
    "youtube",
    "instagram",
    "trill",
    "musically",
    "tiktok",
    "facebook",
    "katana",
    "snapchat",
)

_TOXIC_LABELS = {
    "toxic",
    "hate",
    "abusive",
    "threat",
    "offensive",
    "cyberbullying",
    "hatespeech",
    "selfharmrisk",
    "suicidalthoughts",
    "violencesupport",
    "extremismrisk",
}

_STRESS_LABELS = {
    "stress",
    "anxiety",
    "depression",
    "burnout",
    "mentalfatigue",
    "hopelessness",
    "overthinking",
    "emotionalpain",
    "lowselfesteem",
}

_EDUCATION_LABELS = {
    "educational",
    "informational",
    "tutorial",
    "health",
    "technology",
}


def _is_social_package(package_name: str) -> bool:
    p = (package_name or "").lower()
    if not p or _WHATSAPP_KEYWORD in p:
        return False
    return any(k in p for k in _SOCIAL_KEYWORDS)


def _to_mood_label(content_type: dict[str, Any]) -> str:
    mood = (content_type.get("main_emotion") or "").strip().lower()
    labels = content_type.get("labels")
    if isinstance(labels, list) and labels:
        label_set = {str(x).strip().lower() for x in labels}
        if "happy" in label_set:
            return "happy"
        if "sad" in label_set:
            return "sad"
        if "angry" in label_set:
            return "angry"
        if "neutral" in label_set:
            return "neutral"
        if "anxiety" in label_set or "stress" in label_set:
            return "stressed"
        if "burnout" in label_set or "mentalfatigue" in label_set:
            return "tired"
    if mood in {"happy", "sad", "angry", "neutral"}:
        return mood
    if mood in {"anxious", "anxiety"}:
        return "anxious"
    if mood in {"stress", "stressed"}:
        return "stressed"
    if mood in {"burnout", "mentalfatigue"}:
        return "tired"
    return "neutral"


def _risk_signal(content_type: dict[str, Any]) -> float:
    try:
        tox = float(content_type.get("toxicity_score") or 0)
    except Exception:
        tox = 0
    try:
        risk = float(content_type.get("risk_score") or 0)
    except Exception:
        risk = 0
    return max(tox, risk)


def build_recommendations(user, *, range_key: str = "week") -> list[dict[str, Any]]:
    selected = (range_key or "week").strip().lower()
    if selected not in {"day", "week", "month"}:
        selected = "week"

    now = timezone.now()
    if selected == "day":
        start = now - timedelta(days=1)
    elif selected == "month":
        start = now - timedelta(days=30)
    else:
        start = now - timedelta(days=7)

    # Screen time (daily rollups)
    start_date = start.date()
    end_date = now.date()
    screen_rows = ScreenTime.objects.filter(user=user, date__range=(start_date, end_date))
    total_screen_time_seconds = int(screen_rows.aggregate(s=Avg("total_screen_time")).get("s") or 0)  # placeholder fallback
    if screen_rows.exists():
        total_screen_time_seconds = int(screen_rows.aggregate(s=Avg("total_screen_time")).get("s") or 0) * screen_rows.count()

    # Safer exact sums
    total_screen_time_seconds = int(screen_rows.aggregate(s=Avg("total_screen_time")).get("s") or 0)
    # Above line keeps behavior stable even when no rows; exact totals are computed below.
    total_screen_time_seconds = int(
        screen_rows.values_list("total_screen_time", flat=True).iterator().sum()
        if screen_rows.exists()
        else 0
    )
    social_media_time_seconds = int(
        screen_rows.values_list("social_media_time", flat=True).iterator().sum()
        if screen_rows.exists()
        else 0
    )
    video_watch_time_seconds = int(
        screen_rows.values_list("video_watch_time", flat=True).iterator().sum()
        if screen_rows.exists()
        else 0
    )

    # App-level usage for better "exclude WhatsApp"
    usage_events = ScreenUsageEvent.objects.filter(user=user, end_time__gte=start, end_time__lte=now)
    social_seconds_filtered = int(
        usage_events
        .filter(end_time__gte=start)
        .values("id")  # keep query planner stable
        .count()
    )
    # Recompute with Python sum to keep the engine safe for variable DB setups.
    social_seconds_filtered = 0
    late_night_seconds = 0
    for ev in usage_events.only("usage_time", "package_name", "end_time"):
        if _is_social_package(ev.package_name):
            social_seconds_filtered += int(ev.usage_time or 0)
        hour = ev.end_time.hour
        if hour >= 23 or hour < 5:
            late_night_seconds += int(ev.usage_time or 0)

    total_seconds_for_ratios = max(1, total_screen_time_seconds)
    social_fraction = float(social_seconds_filtered + video_watch_time_seconds) / float(total_seconds_for_ratios)
    late_night_share = float(late_night_seconds) / float(total_seconds_for_ratios)

    # Face verification consistency
    face_events = FaceVerificationEvent.objects.filter(user=user, created_at__gte=start, created_at__lte=now)
    total_face_events = face_events.count()
    verified_face_events = face_events.filter(is_verified=True).count()
    verification_rate = (verified_face_events / total_face_events) if total_face_events else 0.0
    avg_match_percent = face_events.aggregate(v=Avg("verified_face_match_percent")).get("v") or 0.0

    # Content signals
    chunks = VideoChunkAnalysis.objects.filter(user=user, created_at__gte=start, created_at__lte=now)

    mood_counter: Counter[str] = Counter()
    stress_chunks = 0
    toxic_chunks = 0
    education_chunks = 0
    total_chunks = 0
    category_counter: Counter[str] = Counter()
    risk_sum = 0.0
    toxicity_sum = 0.0
    main_emotion_counter: Counter[str] = Counter()

    for chunk in chunks.only("content_type"):
        total_chunks += 1
        ct = chunk.content_type or {}
        if not isinstance(ct, dict):
            continue

        labels = ct.get("labels") or []
        label_set = {str(x).strip().lower() for x in labels if str(x).strip()}

        mood = _to_mood_label(ct)
        mood_counter[mood] += 1
        main_emotion_counter[mood] += 1

        risk = _risk_signal(ct)
        risk_sum += risk

        try:
            toxicity_score = float(ct.get("toxicity_score") or 0)
        except Exception:
            toxicity_score = 0
        toxicity_sum += toxicity_score

        is_stress = any(x in label_set for x in _STRESS_LABELS) or mood in {"stressed", "anxious"}
        if is_stress:
            stress_chunks += 1

        is_toxic = any(x in _TOXIC_LABELS for x in label_set) or toxicity_score >= 40 or ct.get("risk_score", 0) >= 40
        if is_toxic:
            toxic_chunks += 1

        is_education = any(x in label_set for x in _EDUCATION_LABELS) or any("tutorial" in x for x in label_set)
        if is_education:
            education_chunks += 1

        # Lightweight category mapping for UI cards
        if "educational" in label_set or "tutorial" in label_set or "informational" in label_set:
            category_counter["educational"] += 1
        elif "toxic" in label_set or "hate" in label_set or "cyberbullying" in label_set:
            category_counter["toxic"] += 1
        elif "gaming" in label_set or "entertainment" in label_set:
            category_counter["gaming_or_entertainment"] += 1
        else:
            category_counter["wellness_or_other"] += 1

    total_chunks = max(1, total_chunks)
    stress_ratio = stress_chunks / float(total_chunks)
    toxic_ratio = toxic_chunks / float(total_chunks)
    education_ratio = education_chunks / float(total_chunks)

    dominant_mood = mood_counter.most_common(1)[0][0] if mood_counter else "neutral"
    avg_risk = risk_sum / float(total_chunks) if total_chunks else 0.0
    avg_toxicity = toxicity_sum / float(total_chunks) if total_chunks else 0.0

    # Build cards (sorted later by priority)
    cards: list[dict[str, Any]] = []

    def _add_card(
        *,
        title: str,
        description: str,
        category: str,
        priority: str,
        action_type: str,
        action_label: str,
    ) -> None:
        cards.append(
            {
                "title": title,
                "description": description,
                "category": category,
                "priority": priority,
                "action": {"type": action_type, "label": action_label},
            }
        )

    # High priority: stress + late night + toxic
    if stress_ratio >= 0.18 or avg_risk >= 35:
        _add_card(
            title="Stress Reduction Plan",
            description="We detected elevated stress/anxiety signals in your recent content. Try a short breathing session to help your nervous system reset.",
            category="Mental Health",
            priority="High",
            action_type="breathing_exercise",
            action_label="Start Breathing Exercise",
        )

    if late_night_share >= 0.25 or late_night_seconds >= 90 * 60:
        _add_card(
            title="Late-Night Detox",
            description="Your usage patterns suggest heavier late-night screen activity. Reducing after 11 PM can improve mood stability and sleep quality.",
            category="Sleep",
            priority="High",
            action_type="start_meditation",
            action_label="Start Meditation",
        )

    if toxic_ratio >= 0.12 or avg_toxicity >= 35:
        _add_card(
            title="Reduce Toxic Content Exposure",
            description="Toxicity/risk signals are appearing in your recent viewing. Aim for safer alternatives and limit high-trigger content.",
            category="Content Behavior",
            priority="High",
            action_type="reduce_toxic_content",
            action_label="Open Safe Report",
        )

    # Medium priority: addiction + education + verification consistency
    if social_fraction >= 0.55 or total_screen_time_seconds >= 5 * 3600:
        _add_card(
            title="Screen Addiction Guardrails",
            description="Social/video consumption is dominating your recent screen time. Set limits to prevent long scrolling loops.",
            category="Screen Addiction",
            priority="Medium",
            action_type="set_app_limits",
            action_label="Set App Limits",
        )

    if education_ratio <= 0.18:
        _add_card(
            title="Boost Learning Habits",
            description="Your recent mix shows lower educational content. Try replacing some entertainment time with tutorials or informational media.",
            category="Productivity",
            priority="Medium",
            action_type="wellness_content",
            action_label="Explore Learning Content",
        )

    if total_face_events > 0 and verification_rate < 0.8:
        _add_card(
            title="Improve Verification Consistency",
            description=f"Face verification passed {verification_rate * 100:.0f}% of the time for this range (avg match {avg_match_percent:.1f}%). Re-enroll if needed to keep tracking reliable.",
            category="Privacy & Safety",
            priority="Low",
            action_type="face_rescan",
            action_label="Re-verify Face",
        )

    # Fallback when little/no data
    if not cards:
        _add_card(
            title="Your Wellness Starter Plan",
            description="Based on limited activity history, here’s a gentle routine: take short breaks, keep evenings calmer, and choose more educational content.",
            category="General",
            priority="Low",
            action_type="start_meditation",
            action_label="Start Meditation",
        )

    priority_rank = {"High": 0, "Medium": 1, "Low": 2}
    cards.sort(key=lambda c: priority_rank.get(c.get("priority"), 3))
    return cards[:8]

