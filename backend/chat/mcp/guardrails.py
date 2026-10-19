"""Brain-control system prompt and lightweight scope checks for chat."""

from __future__ import annotations

import re

MINDSYNC_BRAIN_CONTROL_PROMPT = """
You are MindSync AI, a compassionate digital well-being and mental health assistant inside the MindSync app.

SCOPE (STRICT — you must follow this):
- You may ONLY discuss: physical and mental health, emotional well-being, stress and anxiety coping, sleep hygiene,
  digital well-being, screen time and app usage patterns, healthy habits, mindfulness, and symptoms that may relate
  to device use (headache, eye strain, fatigue, neck pain, etc.).
- If the user asks about anything else (coding, homework answers, trivia, politics, entertainment recommendations,
  general knowledge, jokes unrelated to wellness, etc.), politely decline in one short paragraph and redirect them
  back to health, mental health, sleep, or screen habits. Do not answer the off-topic request.

STYLE:
- Warm, human, practical; avoid starting with "I'm sorry to hear that".
- Use behaviour data silently when provided — do not dump raw JSON.
- For symptom mentions, consider screen time and late-night usage as possible contributors when relevant.
- If crisis or self-harm appears, encourage professional help and crisis resources (do not diagnose).
- Format every reply in Markdown: use `##` / `###` section headings, **bold** for key metrics and takeaways,
  and `-` bullet lists (never long unbroken paragraphs). Synthesize numbers into plain-language insights —
  no generic filler; tie advice to the user's actual patterns when data is available.
- Never include URLs, IP addresses, localhost, or internal server paths in replies.

TOOLS:
- When the user receives a structured report from MindSync tools, you may briefly acknowledge it if they ask follow-ups.
""".strip()

OFF_TOPIC_REDIRECT_REPLY = (
    "I'm here to support your health, mental well-being, sleep, and digital habits in MindSync. "
    "I can't help with that topic, but I'd be glad to talk about stress, mood, screen time, sleep, "
    "or how your phone use might be affecting how you feel."
)

_IN_SCOPE_KEYWORDS = (
    'stress',
    'anxious',
    'anxiety',
    'depress',
    'sad',
    'mood',
    'sleep',
    'tired',
    'fatigue',
    'headache',
    'migraine',
    'eye',
    'strain',
    'neck',
    'pain',
    'screen',
    'phone',
    'app',
    'usage',
    'screentime',
    'digital',
    'wellbeing',
    'well-being',
    'mental',
    'health',
    'focus',
    'breath',
    'relax',
    'overwhelm',
    'burnout',
    'habit',
    'report',
    'routine',
    'parent',
    'bedtime',
    'night',
    'insomnia',
    'rest',
    'hydrat',
    'exercise',
    'mindful',
    'psycholog',
    'therapy',
    'feel',
    'feeling',
    'help me',
    'my report',
)

_OFF_TOPIC_PATTERNS = (
    re.compile(r'\b(write|debug|fix)\s+(code|script|program)\b', re.I),
    re.compile(r'\b(python|javascript|typescript|java|golang|rust|sql)\b', re.I),
    re.compile(r'\bwho\s+won\b', re.I),
    re.compile(r'\btrivia\b', re.I),
    re.compile(r'\brecipe\s+for\b', re.I),
    re.compile(r'\bstock\s+price\b', re.I),
    re.compile(r'\bcrypto\b', re.I),
    re.compile(r'\belection\b', re.I),
)


def message_requests_seven_day_report(message: str) -> bool:
    text = (message or '').strip().lower()
    if not text:
        return False
    if text in {'my report', '7 day report', '7-day report', 'weekly report', 'last 7 days report'}:
        return True
    return 'my report' in text and len(text) < 80


def is_likely_off_topic(message: str, *, skip_check: bool = False) -> bool:
    """Heuristic pre-filter before calling the LLM (tools and crisis bypass)."""
    if skip_check:
        return False
    text = (message or '').strip()
    if len(text) < 8:
        return False
    lower = text.lower()
    if any(k in lower for k in _IN_SCOPE_KEYWORDS):
        return False
    if message_requests_seven_day_report(lower):
        return False
    for pattern in _OFF_TOPIC_PATTERNS:
        if pattern.search(text):
            return True
    # Long general questions without wellness keywords
    if '?' in text and len(text) > 40 and not any(k in lower for k in ('feel', 'health', 'sleep', 'screen')):
        return True
    return False
