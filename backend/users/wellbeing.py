"""Aggregate last-7-days signals for wellbeing, mental-health UI, mood and reports."""

from __future__ import annotations

import math
from collections import Counter, defaultdict
from datetime import timedelta

from django.utils import timezone

from tracking.models import ScreenTime


def _label_texts(ct: dict) -> list[str]:
    if not isinstance(ct, dict):
        return []
    out: list[str] = []
    for k in ("main_emotion", "summary"):
        v = ct.get(k)
        if isinstance(v, str) and v.strip():
            out.append(v.lower())
    lbls = ct.get("labels")
    if isinstance(lbls, list):
        for x in lbls:
            if isinstance(x, str) and x.strip():
                out.append(x.lower())
    return out


_STRESS_KEYS = frozenset({"stress", "burnout", "frustration", "anger / irritability", "emotional exhaustion", "panic attacks"})
_ANX_KEYS = frozenset({"anxiety", "fear / panic", "overthinking", "panic attacks"})
_DEP_KEYS = frozenset({"depression", "hopelessness", "loneliness", "severe depression indicators", "suicidal ideation signals"})
_VIOL_KEYS = frozenset({"anger / irritability", "violent"})
_ENT_KEYS = frozenset({"entertainment", "relaxation"})
_EDU_KEYS = frozenset({"educational", "motivation"})
_POS_KEYS = frozenset(
    {"happiness", "joy", "calm", "gratitude", "hopefulness", "relaxation", "peacefulness"}
)


def _bucket_counts(chunks_iter) -> dict[str, int]:
    buckets = Counter()
    for chunk in chunks_iter:
        texts = _label_texts(chunk.content_type or {})
        joined = " ".join(texts)
        if any(s in joined for s in _STRESS_KEYS) or "stress" in joined:
            buckets["stress_content"] += 1
        if any(s in joined for s in _ANX_KEYS) or "anxiety" in joined:
            buckets["anxiety_content"] += 1
        if any(s in joined for s in _DEP_KEYS) or "depress" in joined:
            buckets["depression_content"] += 1
        if any(s in joined for s in _VIOL_KEYS) or "violent" in joined:
            buckets["violent_content"] += 1
        if any(s in joined for s in _EDU_KEYS) or "education" in joined:
            buckets["educational_content"] += 1
        elif any(s in joined for s in _ENT_KEYS) or "tiktok" in chunk.source_package or "youtube" in (chunk.source_package or ""):
            buckets["entertainment_content"] += 1
        if any(s in joined for s in _POS_KEYS) or ("positive" in joined):
            buckets["positive_content"] += 1
    return dict(buckets)


def _apply_face_mood_to_dashboard(payload: dict, user, days: int) -> dict:
    """Overlay FaceMoodScan labels onto mood_last_7 when present."""
    try:
        from users.services.mood_weekly_service import build_weekly_mood_payload

        mood_payload = build_weekly_mood_payload(user, request=None)
        if mood_payload.get('has_graph_data') or mood_payload.get('entry_count', 0) > 0:
            latest = str(mood_payload.get('latest_mood') or '').strip()
            dom = str(mood_payload.get('dominant_mood') or '').strip()
            payload['dominant_mood_week'] = (latest or dom or payload.get('dominant_mood_week') or 'neutral').lower()
            payload['mood_weekly_live'] = mood_payload
        days_list = mood_payload.get('days') or []
        if days_list:
            merged = []
            for i in range(days - 1, -1, -1):
                d = (timezone.localdate() - timedelta(days=i)).isoformat()
                day_row = next((x for x in days_list if x.get('date') == d), None)
                if day_row and day_row.get('label'):
                    merged.append({
                        'date': d,
                        'dominant_mood': str(day_row['label']).lower(),
                        'samples': int(day_row.get('entries') or 0),
                        'media': day_row.get('media') or [],
                    })
                else:
                    old = next((x for x in payload.get('mood_last_7', []) if x.get('date') == d), None)
                    merged.append(old or {'date': d, 'dominant_mood': 'neutral', 'samples': 0})
            payload['mood_last_7'] = merged
        insights = mood_payload.get('insights') or {}
        if insights.get('has_data') and not payload.get('mental_health', {}).get('has_data'):
            payload['stress_indicator'] = int(round(insights.get('avg_stress') or 0))
            payload['anxiety_indicator'] = int(round(insights.get('avg_anxiety') or 0))
            payload['depression_indicator'] = int(round(insights.get('avg_depression') or 0))
    except Exception:
        pass
    today = timezone.localdate()
    row = ScreenTime.objects.filter(user=user, date=today).first()
    payload["sleep_seconds_today"] = int(row.sleep_time) if row else 0
    payload["late_night_seconds_today"] = int(row.late_night_activity) if row else 0
    return payload


def build_wellness_dashboard(user, days: int = 7) -> dict:
    from users.mental_health_scoring import compute_mental_health_scores
    from users.models import VideoChunkAnalysis

    mental_health = compute_mental_health_scores(user, window_days=days)

    end = timezone.now()
    start = end - timedelta(days=days)

    chunks = list(
        VideoChunkAnalysis.objects.filter(user=user, created_at__gte=start, created_at__lte=end).order_by("created_at")
    )
    n_chunks = len(chunks)

    start_d = timezone.localdate() - timedelta(days=days - 1)
    screen_minutes_week = _screen_aggregate(user, start_d)
    mood_last_7 = []
    for i in range(days - 1, -1, -1):
        d = (timezone.localdate() - timedelta(days=i)).isoformat()
        mood_last_7.append({"date": d, "dominant_mood": "neutral", "samples": 0})

    def _has_wellbeing_signal(score: int, mh: dict, chunks: int) -> bool:
        return chunks > 0 or bool(mh.get("has_data")) or score > 0

    if n_chunks == 0:
        if not mental_health.get("has_data"):
            return _apply_face_mood_to_dashboard(
                {
                    "window_days": days,
                    "has_wellbeing_signal": False,
                    "wellbeing_score": 0,
                    "mental_health_score": 0,
                    "stress_indicator": 0,
                    "anxiety_indicator": 0,
                    "depression_indicator": 0,
                    "dominant_mood_week": "neutral",
                    "mood_last_7": mood_last_7,
                    "content_bucket_counts": [],
                    "total_chunks": 0,
                    "screen_minutes_week": screen_minutes_week,
                    "facet_summary": "Scores start at zero until analysed video clips arrive. Screen time below is already tracked.",
                    "mental_health": mental_health,
                },
                user,
                days,
            )
        overall = float(mental_health["overall"]["score"])
        wb = int(round(max(0, 100 - overall)))
        return _apply_face_mood_to_dashboard(
            {
                "window_days": days,
                "has_wellbeing_signal": _has_wellbeing_signal(wb, mental_health, 0),
                "wellbeing_score": wb,
                "mental_health_score": int(round(overall)),
                "stress_indicator": int(round(mental_health["stress"]["score"])),
                "anxiety_indicator": 0,
                "depression_indicator": int(round(mental_health["depression"]["score"])),
                "dominant_mood_week": "neutral",
                "mood_last_7": mood_last_7,
                "content_bucket_counts": [],
                "total_chunks": 0,
                "screen_minutes_week": screen_minutes_week,
                "facet_summary": "Scores from facial expression and screen-time behaviour data.",
                "mental_health": mental_health,
            },
            user,
            days,
        )

    mh_vals: list[float] = []
    sent_vals: list[float] = []
    risk_vals: list[float] = []
    mood_by_day: dict = defaultdict(list)

    for c in chunks:
        ct = c.content_type or {}
        mh = float(ct.get("mental_health_score") or 0)
        ss = float(ct.get("sentiment_score") or 50)
        rk = float(ct.get("risk_score") or 0)
        mh_vals.append(min(100, max(0, mh)))
        sent_vals.append(min(100, max(0, ss)))
        risk_vals.append(min(100, max(0, rk)))

        mood = ((ct.get("main_emotion") or "neutral")).strip().lower() or "neutral"
        day = timezone.localtime(c.created_at).date().isoformat()
        mood_by_day[day].append(mood)

    avg_mh = sum(mh_vals) / len(mh_vals)
    avg_sent = sum(sent_vals) / len(sent_vals)
    avg_risk = sum(risk_vals) / len(risk_vals)

    # Starts at 0 with no data; with data climbs from sentiment & inverse distress.
    positivity = avg_sent / 100.0
    distress = (avg_mh + avg_risk) / 200.0
    raw_score = max(0.0, min(1.0, positivity * (1 - distress * 0.85))) * (1 - math.exp(-n_chunks / 6))
    wellbeing_score = int(round(raw_score * 100))
    mental_health_score = int(round(max(0, 100 - avg_mh * 0.7 - avg_risk * 0.3)))

    if mental_health.get("has_data"):
        mh_wellbeing = int(round(max(0, 100 - float(mental_health["overall"]["score"]))))
        wellbeing_score = (
            mh_wellbeing
            if n_chunks == 0
            else int(round((wellbeing_score + mh_wellbeing) / 2))
        )

    bc = _bucket_counts(chunks)
    total_buckets = sum(bc.values()) or 1

    def pct(x: int) -> float:
        return round(100.0 * x / total_buckets, 1)

    content_bucket_counts = [
        {"key": k, "label": _bucket_label(k), "count": v, "percent": pct(v)}
        for k, v in sorted(bc.items(), key=lambda kv: kv[1], reverse=True)
    ]

    if mental_health.get("has_data"):
        stress_i = int(round(mental_health["stress"]["score"]))
        anx_i = 0
        dep_i = int(round(mental_health["depression"]["score"]))
    else:
        stress_i = 0
        anx_i = 0
        dep_i = 0

    mood_counts = Counter()
    for c in chunks:
        m = str((c.content_type or {}).get("main_emotion") or "neutral").strip().lower()
        mood_counts[m or "neutral"] += 1
    dominant_mood_week = mood_counts.most_common(1)[0][0] if mood_counts else "neutral"

    mood_last_7 = []
    for i in range(days - 1, -1, -1):
        d = (timezone.localdate() - timedelta(days=i)).isoformat()
        moods = mood_by_day.get(d, [])
        top = moods[-1] if moods else dominant_mood_week
        mood_last_7.append({"date": d, "dominant_mood": top, "samples": len(moods)})

    mh_summary = ""
    if mental_health.get("has_data"):
        mh_summary = (
            f" Stress {mental_health['stress']['score']},"
            f" depression {mental_health['depression']['score']}."
        )

    return _apply_face_mood_to_dashboard(
        {
            "window_days": days,
            "has_wellbeing_signal": _has_wellbeing_signal(
                wellbeing_score, mental_health, n_chunks
            ),
            "wellbeing_score": wellbeing_score,
            "mental_health_score": mental_health_score,
            "stress_indicator": stress_i,
            "anxiety_indicator": anx_i,
            "depression_indicator": dep_i,
            "dominant_mood_week": dominant_mood_week,
            "mood_last_7": mood_last_7,
            "content_bucket_counts": content_bucket_counts,
            "total_chunks": n_chunks,
            "screen_minutes_week": screen_minutes_week,
            "facet_summary": f"Derived from {n_chunks} analysed clip(s); dominant mood signal: {dominant_mood_week}.{mh_summary}",
            "mental_health": mental_health,
        },
        user,
        days,
    )


def content_theme_buckets_for_analytics(user, start_at, end_at):
    """Themed categories (stress/education/etc.) as list for Analytics UI."""

    from users.models import VideoChunkAnalysis

    chunks = list(
        VideoChunkAnalysis.objects.filter(
            user=user,
            created_at__gte=start_at,
            created_at__lte=end_at,
        )
    )
    if not chunks:
        return []
    bc = _bucket_counts(chunks)
    total = sum(bc.values()) or 1

    def pct(x: int) -> float:
        return round(100.0 * x / total, 1)

    return [
        {"category": _bucket_label(k), "count": v, "percent": pct(v), "key": k}
        for k, v in sorted(bc.items(), key=lambda kv: kv[1], reverse=True)
    ]


def _bucket_label(key: str) -> str:
    return {
        "stress_content": "Stress-oriented content",
        "anxiety_content": "Anxiety-oriented content",
        "depression_content": "Depression-oriented content",
        "violent_content": "Violent / intense content",
        "educational_content": "Educational content",
        "entertainment_content": "Entertainment content",
        "positive_content": "Positive / uplifting content",
    }.get(key, key.replace("_", " ").title())


def build_weekly_report_text(user, days: int = 7) -> dict:
    from users.models import AppUsage

    dash = build_wellness_dashboard(user, days=days)

    end_d = timezone.localdate()
    start_d = end_d - timedelta(days=days - 1)

    qs = AppUsage.objects.filter(user=user, date__gte=start_d)
    agg = defaultdict(int)
    for row in qs:
        agg[row.app_name] += row.duration_seconds

    top_apps = sorted(agg.items(), key=lambda x: x[1], reverse=True)[:8]

    lines = [
        f"MindSync — {days}-day wellbeing snapshot",
        f"Well-being score: {dash['wellbeing_score']} / 100",
        f"Mental wellness index: {dash['mental_health_score']} / 100",
        f"Stress / anxiety / depression indicators: {dash['stress_indicator']} / {dash['anxiety_indicator']} / {dash['depression_indicator']}",
        f"Analysed video chunks: {dash['total_chunks']}",
        f"Approx. screen-on (tracked days): ~{dash['screen_minutes_week']} minutes total",
        f"Dominant mood trend: {dash['dominant_mood_week']}",
        "",
        "Top categories (from content signals):",
    ]
    for item in dash.get("content_bucket_counts") or []:
        lines.append(f"- {item.get('label')}: {item.get('percent')}% ({item.get('count')} clips)")

    lines += ["", "Most-used apps (by reported duration):"]
    for name, secs in top_apps:
        m = secs // 60
        lines.append(f"- {name}: ~{m} min")

    return {"title": f"Last {days} days · MindSync Report", "body": "\n".join(lines), "dashboard": dash}


# Fix erroneous placeholder in aggregation — use Django Sum
def _screen_aggregate(user, start_d):
    from django.db.models import Sum

    total = ScreenTime.objects.filter(user=user, date__gte=start_d).aggregate(s=Sum("total_screen_time"))["s"]
    return int(total or 0) // 60
