"""Remove URLs and dev-only details from chat text returned to clients."""

from __future__ import annotations

import re

_URL_RE = re.compile(r'https?://[^\s\)\]]+', re.IGNORECASE)
_LOCAL_RE = re.compile(r'\b(?:127\.0\.0\.1|localhost)(?::\d+)?\b', re.IGNORECASE)
_ADB_RE = re.compile(r'adb\s+reverse[^\n.]*', re.IGNORECASE)


def sanitize_chat_reply(text: str) -> str:
    if not text:
        return text
    out = text.strip()
    out = _URL_RE.sub('[link removed]', out)
    out = _LOCAL_RE.sub('[server]', out)
    out = _ADB_RE.sub('', out)
    out = re.sub(r'\n{3,}', '\n\n', out)
    return out.strip()
