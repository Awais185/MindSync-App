"""
Aggregate VideoChunkAnalysis.content_type into user-facing category session stats.
"""

from __future__ import annotations

import re
from collections import Counter
from typing import Any

# Canonical labels shown in Analytics → Category Session
CANONICAL_CATEGORIES = (
    'Social Media',
    'Entertainment',
    'Educational',
    'Gaming',
    'News & Info',
    'Health & Wellness',
    'Other',
)

_SOCIAL_PKG_HINTS = (
    'instagram',
    'tiktok',
    'musically',
    'trill',
    'facebook',
    'snapchat',
    'twitter',
    'whatsapp',
    'telegram',
    'youtube',
    'reddit',
    'threads',
    'linkedin',
    'pinterest',
)

_GAMING_PKG_HINTS = (
    'roblox',
    'minecraft',
    'pubg',
    'fortnite',
    'callofduty',
    'activision',
    'epicgames',
    'supercell',
    'king.candycrush',
    'game',
)

_EDU_TEXT_HINTS = (
    'educational',
    'education',
    'tutorial',
    'learn',
    'course',
    'study',
    'motivation',
    'inspirational',
    'deep thinking',
    'philosophical',
    'self-introspection',
)

_ENT_TEXT_HINTS = (
    'entertainment',
    'relaxation',
    'comedy',
    'funny',
    'viral',
    'meme',
    'music video',
    'movie',
    'show',
)

_HEALTH_TEXT_HINTS = (
    'wellness',
    'meditation',
    'mindful',
    'mental health',
    'therapy',
    'self-care',
    'sleep',
    'fitness',
)

_NEWS_TEXT_HINTS = (
    'news',
    'politics',
    'current events',
    'headline',
)


def _normalize_display_name(raw: str) -> str:
    s = re.sub(r'\s+', ' ', (raw or '').strip())
    if not s:
        return 'Other'
    low = s.lower().replace('_', ' ')
    aliases = {
        'social': 'Social Media',
        'social media': 'Social Media',
        'social_media': 'Social Media',
        'entertainment': 'Entertainment',
        'entertainment content': 'Entertainment',
        'educational': 'Educational',
        'education': 'Educational',
        'gaming': 'Gaming',
        'games': 'Gaming',
        'game': 'Gaming',
        'news': 'News & Info',
        'news & info': 'News & Info',
        'health': 'Health & Wellness',
        'wellness': 'Health & Wellness',
        'neutral': 'Other',
        'other': 'Other',
    }
    if low in aliases:
        return aliases[low]
    for key, label in aliases.items():
        if key in low and len(key) > 3:
            return label
    titled = s.title()
    if titled in CANONICAL_CATEGORIES:
        return titled
    return titled if len(titled) <= 40 else 'Other'


def _package_category(source_package: str | None) -> str | None:
    pkg = (source_package or '').lower()
    if not pkg:
        return None
    if any(h in pkg for h in _GAMING_PKG_HINTS):
        return 'Gaming'
    if any(h in pkg for h in _SOCIAL_PKG_HINTS):
        return 'Social Media'
    return None


def _text_blob(content_type: dict) -> str:
    parts: list[str] = []
    for key in ('content_type', 'category', 'content_category', 'main_emotion', 'summary'):
        v = content_type.get(key)
        if isinstance(v, str) and v.strip():
            parts.append(v.strip().lower())
    labels = content_type.get('labels')
    if isinstance(labels, list):
        for item in labels:
            if isinstance(item, str) and item.strip():
                parts.append(item.strip().lower())
    return ' '.join(parts)


def _category_from_text(blob: str) -> str | None:
    if not blob:
        return None
    if any(h in blob for h in _EDU_TEXT_HINTS):
        return 'Educational'
    if any(h in blob for h in _NEWS_TEXT_HINTS):
        return 'News & Info'
    if any(h in blob for h in _HEALTH_TEXT_HINTS):
        return 'Health & Wellness'
    if any(h in blob for h in _ENT_TEXT_HINTS):
        return 'Entertainment'
    if 'social media' in blob or 'addiction behavior' in blob:
        return 'Social Media'
    if 'game' in blob or 'gaming' in blob:
        return 'Gaming'
    return None


def session_category_for_chunk(content_type: Any, source_package: str | None = None) -> str:
    """Pick one canonical category per analysed chunk."""
    if not isinstance(content_type, dict) or not content_type:
        pkg_cat = _package_category(source_package)
        return pkg_cat or 'Other'

    direct = content_type.get('content_type') or content_type.get('category') or content_type.get(
        'content_category'
    )
    if isinstance(direct, str) and direct.strip():
        return _normalize_display_name(direct)

    pkg_cat = _package_category(source_package)
    text_cat = _category_from_text(_text_blob(content_type))
    if text_cat:
        return text_cat
    if pkg_cat:
        return pkg_cat
    return 'Other'


def build_category_session(user, start_at, end_at) -> dict[str, Any]:
    """
    Returns category_session payload for Analytics UI.
    Counts one category per VideoChunkAnalysis row for the authenticated user.
    """
    from users.services.behavioral_insights_analytics import _video_chunks_in_range

    chunks = _video_chunks_in_range(user, start_at, end_at).only(
        'content_type',
        'source_package',
        'created_at',
    )

    counts: Counter[str] = Counter()
    for chunk in chunks.iterator(chunk_size=200):
        cat = session_category_for_chunk(chunk.content_type, chunk.source_package)
        counts[cat] += 1

    total = sum(counts.values())
    if total == 0:
        return {
            'categories': [],
            'total_chunks': 0,
            'top_category': None,
            'top_category_percent': 0.0,
            'has_data': False,
        }

    sorted_items = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    categories = [
        {
            'category': name,
            'count': count,
            'percent': round((count / total) * 100.0, 1),
        }
        for name, count in sorted_items
    ]
    top_name, top_count = sorted_items[0]
    return {
        'categories': categories,
        'total_chunks': total,
        'top_category': top_name,
        'top_category_percent': round((top_count / total) * 100.0, 1),
        'has_data': True,
    }
