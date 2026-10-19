"""AI-generated weekly report recommendations from the full saved report payload."""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from django.contrib.auth.models import User

logger = logging.getLogger(__name__)

_RECOMMEND_SYSTEM = """You are MindSync's digital wellbeing coach. You receive a JSON summary of one user's last 7 days
(screen time, tracked sleep, late-night phone use, facial emotion captures, stress/depression scores, content types, risks).

Respond with ONLY valid JSON (no markdown fences) using this schema:
{
  "for_user": ["bullet 1", "bullet 2", ...],
  "sections": [
    {"title": "Sleep & recovery", "bullets": ["...", "..."]},
    {"title": "Screen habits", "bullets": ["..."]},
    {"title": "Emotional wellbeing", "bullets": ["..."]}
  ],
  "summary_line": "One encouraging sentence tying the week together."
}

Rules:
- 4–6 for_user bullets, each specific to the JSON (name apps, hours, emotions, scores when present).
- 2–4 sections with 2–3 bullets each; skip a section if there is no data for it.
- Never diagnose; use supportive, actionable language.
- If data is sparse, say what to log (face scans, screen permission) instead of generic wellness tips.
- Do not invent numbers not in the JSON."""


def _compact_report_for_ai(payload: dict[str, Any]) -> dict[str, Any]:
    seven = []
    for row in (payload.get('seven_day_data') or [])[:7]:
        if not isinstance(row, dict):
            continue
        seven.append(
            {
                'date': row.get('date'),
                'screen_h': round(int(row.get('total_screen_time') or 0) / 3600.0, 2),
                'sleep_h': row.get('sleep_time_hours'),
                'sleep_tracked': row.get('sleep_data_source') == 'screen_time_table',
                'late_night_h': round(int(row.get('late_night_usage_seconds') or 0) / 3600.0, 2),
                'emotion': row.get('emotion') or row.get('dominant_mood'),
                'depression': row.get('depression_score'),
                'stress': row.get('stress_score'),
            }
        )
    cond = payload.get('condition_breakdown') if isinstance(payload.get('condition_breakdown'), dict) else {}
    snap = payload.get('wellbeing_snapshot') if isinstance(payload.get('wellbeing_snapshot'), dict) else {}
    analytics = payload.get('analytics') if isinstance(payload.get('analytics'), dict) else {}
    risk = payload.get('risk_level') if isinstance(payload.get('risk_level'), dict) else {}
    rec_existing = payload.get('recommendations') if isinstance(payload.get('recommendations'), dict) else {}
    return {
        'user': (payload.get('user') or {}).get('full_name'),
        'period': (payload.get('user') or {}).get('report_period'),
        'wellbeing_snapshot': snap,
        'condition_averages': cond.get('averages'),
        'risk_level': risk,
        'seven_day': seven,
        'late_night_hours_trend': analytics.get('late_night_usage_hours'),
        'avg_sleep_score': (analytics.get('progress_cards') or {}).get('avg_sleep_score'),
        'mental_health_summary': analytics.get('mental_health_summary'),
        'content_top': (analytics.get('content_type_top3') or [])[:3],
        'insights': (payload.get('ai_insights') or [])[:5],
        'prior_generic_recs': (rec_existing.get('for_user') or [])[:2],
    }


def _parse_json_reply(raw: str) -> dict[str, Any] | None:
    text = (raw or '').strip()
    if not text:
        return None
    fence = re.search(r'```(?:json)?\s*([\s\S]*?)```', text)
    if fence:
        text = fence.group(1).strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start = text.find('{')
        end = text.rfind('}')
        if start < 0 or end <= start:
            return None
        try:
            data = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return None
    if not isinstance(data, dict):
        return None
    return data


def _fallback_recommendations(payload: dict[str, Any]) -> dict[str, Any]:
    seven = payload.get('seven_day_data') or []
    tracked = sum(
        1 for r in seven if isinstance(r, dict) and r.get('sleep_data_source') == 'screen_time_table'
    )
    late = sum(
        int(r.get('late_night_usage_seconds') or 0) for r in seven if isinstance(r, dict)
    )
    bullets: list[str] = []
    if tracked:
        bullets.append(
            f'Sleep was tracked on {tracked} night(s) this week — keep a consistent wind-down before bed.'
        )
    else:
        bullets.append(
            'Enable screen-time tracking so MindSync can record sleep hours from your phone usage pattern.'
        )
    if late > 3600:
        bullets.append(
            f'Late-night phone use totaled about {late // 3600}h — try moving stimulating apps earlier in the day.'
        )
    snap = payload.get('wellbeing_snapshot') if isinstance(payload.get('wellbeing_snapshot'), dict) else {}
    emo = (snap.get('latest_emotion') or '').strip()
    if emo:
        bullets.append(f'Latest detected emotion: {emo}. Note what you were doing when scans showed shifts across the week.')
    bullets.append('Complete short face scans on low and high screen days to sharpen your depression and emotion trends.')
    return {
        'for_user': bullets[:6],
        'for_psychologist': [],
        'sections': [],
        'summary_line': bullets[0] if bullets else 'Log more activity to unlock personalized guidance.',
        'source': 'fallback',
    }


def generate_weekly_recommendations(user: User, payload: dict[str, Any]) -> dict[str, Any]:
    """Return recommendations dict; uses Gemini when configured, else data-aware fallback."""
    brief = _compact_report_for_ai(payload)
    if not brief.get('seven_day') and not brief.get('wellbeing_snapshot'):
        return _fallback_recommendations(payload)

    try:
        from chat.views import GeminiChatUnavailable, _generate_gemini_chat_reply

        prompt = (
            'Generate personalized recommendations from this 7-day report JSON:\n'
            + json.dumps(brief, ensure_ascii=False, default=str)
        )
        import os

        prev_max = os.environ.get('GEMINI_CHAT_MAX_TOKENS')
        os.environ['GEMINI_CHAT_MAX_TOKENS'] = '1024'
        try:
            raw = _generate_gemini_chat_reply(
                prompt,
                [],
                system_prompt=_RECOMMEND_SYSTEM,
            )
        finally:
            if prev_max is None:
                os.environ.pop('GEMINI_CHAT_MAX_TOKENS', None)
            else:
                os.environ['GEMINI_CHAT_MAX_TOKENS'] = prev_max
        parsed = _parse_json_reply(raw)
        if not parsed:
            raise ValueError('invalid_json')
        for_user = parsed.get('for_user') or []
        if not isinstance(for_user, list):
            for_user = []
        for_user = [str(s).strip() for s in for_user if str(s).strip()]
        sections = parsed.get('sections') or []
        if not isinstance(sections, list):
            sections = []
        summary_line = str(parsed.get('summary_line') or '').strip()
        if not for_user and sections:
            for sec in sections:
                if isinstance(sec, dict):
                    for_user.extend([str(b) for b in (sec.get('bullets') or [])[:2]])
        if not for_user:
            return _fallback_recommendations(payload)
        return {
            'for_user': for_user[:8],
            'for_psychologist': parsed.get('for_psychologist') or [],
            'sections': sections[:5],
            'summary_line': summary_line or for_user[0],
            'source': 'gemini',
        }
    except Exception as exc:
        logger.info('Weekly report AI recommendations unavailable for user %s: %s', user.id, exc)
        return _fallback_recommendations(payload)
