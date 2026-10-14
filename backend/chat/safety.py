"""
Crisis / self-harm detection — never rely on the LLM alone for this.
"""
from __future__ import annotations

import re

# Word-boundary patterns (common phrases).
_CRISIS_RE = re.compile(
    r"\b("
    r"kill\s*myself|kill\s*my\s*self|end\s*my\s*life|end\s*it\s*all|"
    r"suicid\w*|sucid\w*|"
    r"self[\s-]?harm|hurt\s*myself|"
    r"want\s*to\s*die|wanna\s*die|don'?t\s*want\s*to\s*live|no\s*reason\s*to\s*live|"
    r"better\s*off\s*dead|can'?t\s*go\s*on|"
    r"attempt\w*\s+(suicid\w*|sucid\w*|to\s*die|my\s*life)|"
    r"took\s*pills|overdose"
    r")\b",
    re.IGNORECASE,
)

# Substrings catch typos / spacing without relying on word boundaries.
_CRISIS_SNIPPETS = (
    "suicide",
    "suicidal",
    "sucide",
    "sucid",
    "self harm",
    "self-harm",
    "kill myself",
    "end my life",
    "want to die",
    "wanna die",
    "dont want to live",
    "don't want to live",
    "attempt suicide",
    "attempted suicide",
    "attempt sucide",
    "attempt suicid",
    "going to kill",
    "going to end it",
)

CRISIS_REPLY = (
    "I'm really glad you reached out. What you're describing sounds serious, and you deserve help right now — "
    "not an app chat. Please contact local emergency services or a crisis line immediately. "
    "In the US: call or text 988. If you're not in the US, search for a crisis line in your country. "
    "You are not alone, and people are trained to support you."
)


def is_crisis_message(text: str) -> bool:
    if not text or not str(text).strip():
        return False
    s = str(text).strip()
    low = s.lower()

    # Prevent false positives for technical/dev prompts that may include words like "attempt".
    tech_context = ("model", "llm", "api", "backend", "django", "prompt", "token", "code")
    explicit_crisis = (
        "kill myself", "suicide", "suicidal", "want to die", "end my life", "self harm", "self-harm"
    )
    if any(k in low for k in tech_context) and not any(k in low for k in explicit_crisis):
        return False

    if _CRISIS_RE.search(s):
        return True
    for snip in _CRISIS_SNIPPETS:
        if snip in low:
            return True
    return False
