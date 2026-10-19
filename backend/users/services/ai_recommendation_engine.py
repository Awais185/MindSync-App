"""7-day cached AI wellness summary for the Recommendations screen."""

from __future__ import annotations

import json
import logging
from datetime import timedelta
from typing import Any

from django.contrib.auth.models import User
from django.utils import timezone

from users.models import UserAIWellnessRecommendation
from users.services.weekly_report_ai import _compact_report_for_ai, _parse_json_reply

logger = logging.getLogger(__name__)

_CACHE_DAYS = 7

_AI_SUMMARY_SYSTEM = """You are MindSync's digital wellbeing coach. You receive JSON for one user's last 7 days:
screen time, late-night phone use, tracked sleep, facial emotion/mood, stress and depression scores.

Respond with ONLY valid JSON (no markdown):
{
  "lines": [
    "Line 1: specific observation from their data",
    "Line 2: meditation or mindfulness tip tailored to their week",
    "Line 3: sleep hygiene advice referencing their sleep/late-night pattern",
    "Line 4: stress or mood guidance using their scores/emotions",
    "Line 5: one concrete daily habit change",
    "Line 6 (optional): encouragement or when to seek support if risk is elevated"
  ],
  "risk_level": "low|moderate|high",
  "main_issues": ["short issue label", "..."]
}

Rules:
- Exactly 5 or 6 lines in "lines"; each 1–2 sentences, scannable, no bullet prefixes.
- Reference real numbers and labels from the JSON when present; never invent metrics.
- Include meditation, sleep hygiene, and actionable mental health steps across the lines.
- Supportive tone; no clinical diagnosis."""


def _fallback_lines(payload: dict[str, Any]) -> list[str]:
    from users.services.weekly_report_ai import _fallback_recommendations

    block = _fallback_recommendations(payload)
    lines = [str(s).strip() for s in (block.get('for_user') or []) if str(s).strip()]
    summary = str(block.get('summary_line') or '').strip()
    if summary and summary not in lines:
        lines.insert(0, summary)
    if len(lines) < 5:
        lines.extend(
            [
                'Try a 5-minute breath-focused meditation after your longest screen block today.',
                'Keep a fixed wind-down: dim screens 45 minutes before bed and charge away from your pillow.',
                'Log a quick face scan on both high- and low-stress days so trends stay accurate.',
                'Swap 15 minutes of passive scrolling for a short walk or stretch break.',
                'Celebrate one small win this week — consistency matters more than perfection.',
            ]
        )
    return lines[:6]


def _generate_lines_with_llm(brief: dict[str, Any]) -> dict[str, Any] | None:
    try:
        from chat.views import _generate_gemini_chat_reply

        prompt = (
            'Analyze this 7-day wellbeing JSON and return the required recommendation lines:\n'
            + json.dumps(brief, ensure_ascii=False, default=str)
        )
        import os

        prev_max = os.environ.get('GEMINI_CHAT_MAX_TOKENS')
        os.environ['GEMINI_CHAT_MAX_TOKENS'] = '768'
        try:
            raw = _generate_gemini_chat_reply(
                prompt,
                [],
                system_prompt=_AI_SUMMARY_SYSTEM,
            )
        finally:
            if prev_max is None:
                os.environ.pop('GEMINI_CHAT_MAX_TOKENS', None)
            else:
                os.environ['GEMINI_CHAT_MAX_TOKENS'] = prev_max
        parsed = _parse_json_reply(raw)
        if not parsed:
            return None
        lines_raw = parsed.get('lines') or []
        if not isinstance(lines_raw, list):
            return None
        lines = [str(s).strip() for s in lines_raw if str(s).strip()]
        if len(lines) < 5:
            return None
        return {
            'lines': lines[:6],
            'risk_level': str(parsed.get('risk_level') or 'moderate').lower()[:16],
            'main_issues': [
                str(x).strip()
                for x in (parsed.get('main_issues') or [])
                if str(x).strip()
            ][:6],
            'source': 'gemini',
        }
    except Exception as exc:
        logger.info('AI recommendation LLM unavailable: %s', exc)
        return None


def _build_report_payload(user: User) -> dict[str, Any]:
    from users.services.weekly_report_builder import build_seven_day_report_payload

    return build_seven_day_report_payload(user)


def get_or_create_ai_wellness_recommendation(
    user: User,
    *,
    force_refresh: bool = False,
) -> dict[str, Any]:
    """
    Return cached recommendation if generated within 7 days; else build from 7-day report + LLM.
    """
    now = timezone.now()
    cutoff = now - timedelta(days=_CACHE_DAYS)
    existing = (
        UserAIWellnessRecommendation.objects.filter(user=user).first()
        if not force_refresh
        else None
    )
    if existing and existing.generated_at >= cutoff and (existing.summary_text or '').strip():
        return _serialize_row(existing, cached=True)

    payload = _build_report_payload(user)
    brief = _compact_report_for_ai(payload)
    generated = _generate_lines_with_llm(brief)
    if not generated:
        lines = _fallback_lines(payload)
        generated = {
            'lines': lines,
            'risk_level': 'moderate',
            'main_issues': [],
            'source': 'fallback',
        }

    lines = generated['lines']
    summary_text = '\n\n'.join(lines)
    end_day = timezone.localdate()
    row, _ = UserAIWellnessRecommendation.objects.update_or_create(
        user=user,
        defaults={
            'summary_text': summary_text,
            'lines': lines,
            'risk_level': generated.get('risk_level') or 'unknown',
            'main_issues': generated.get('main_issues') or [],
            'source': generated.get('source') or 'fallback',
            'report_window_end': end_day,
            'generated_at': now,
        },
    )
    return _serialize_row(row, cached=False)


def _serialize_row(row: UserAIWellnessRecommendation, *, cached: bool) -> dict[str, Any]:
    lines = row.lines if isinstance(row.lines, list) else []
    lines = [str(x).strip() for x in lines if str(x).strip()]
    summary = (row.summary_text or '').strip() or '\n\n'.join(lines)
    return {
        'cached': cached,
        'generated_at': row.generated_at.isoformat() if row.generated_at else None,
        'cache_expires_at': (
            (row.generated_at + timedelta(days=_CACHE_DAYS)).isoformat()
            if row.generated_at
            else None
        ),
        'source': row.source or 'fallback',
        'summary_text': summary,
        'lines': lines,
        'risk_level': row.risk_level or 'unknown',
        'main_issues': row.main_issues if isinstance(row.main_issues, list) else [],
    }
