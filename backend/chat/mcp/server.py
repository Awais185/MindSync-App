"""FastMCP server exposing MindSync chat tools (in-process with Django)."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

logger = logging.getLogger(__name__)

_mcp_instance = None

if TYPE_CHECKING:
    from fastmcp import FastMCP


def get_mindsync_mcp():
    """Lazy singleton FastMCP server with registered tool metadata."""
    global _mcp_instance
    if _mcp_instance is not None:
        return _mcp_instance

    try:
        from fastmcp import FastMCP
    except ImportError:
        logger.warning('fastmcp is not installed; MCP server tools run via router only.')
        return None

    mcp = FastMCP(
        'MindSync Chat Tools',
        instructions=(
            'Structured wellness tools for MindSync Digital Psychologist. '
            'Tools require an authenticated Django user and are invoked server-side.'
        ),
    )

    @mcp.tool(
        name='seven_day_comprehensive_report',
        description=(
            'Aggregate the last 7 days of screen time, late-night usage, facial/mood metrics, '
            'alerts, and improvement insights for the current user.'
        ),
    )
    def seven_day_comprehensive_report() -> str:
        return (
            'Invoke via MindSync API (POST /api/chat/) with '
            'tool=seven_day_comprehensive_report for the authenticated user.'
        )

    @mcp.tool(
        name='symptom_usage_diagnostic_24h',
        description=(
            'When the user reports headache, eye strain, fatigue, or neck pain, analyze the last '
            '24 hours of screen/app usage and return correlated guidance.'
        ),
    )
    def symptom_usage_diagnostic_24h(symptom_note: str = '') -> str:
        return (
            'Invoke via MindSync API (POST /api/chat/) when symptoms are detected or '
            f'symptom_note is provided ({symptom_note!r}).'
        )

    _mcp_instance = mcp
    return _mcp_instance
