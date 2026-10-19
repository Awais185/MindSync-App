"""Resolve and execute FastMCP chat tools for authenticated users."""

from __future__ import annotations

from typing import Any

from django.contrib.auth.models import User

from .guardrails import message_requests_seven_day_report
from .report_tools import (
    build_seven_day_comprehensive_report,
    build_symptom_diagnostic_report,
    extract_reported_symptoms,
)

TOOL_SEVEN_DAY_REPORT = 'seven_day_comprehensive_report'
TOOL_SYMPTOM_DIAGNOSTIC = 'symptom_usage_diagnostic_24h'

_VALID_TOOLS = frozenset({TOOL_SEVEN_DAY_REPORT, TOOL_SYMPTOM_DIAGNOSTIC})


def detect_symptom_tool(message: str) -> str | None:
    if extract_reported_symptoms(message):
        return TOOL_SYMPTOM_DIAGNOSTIC
    return None


def resolve_requested_tool(message: str, explicit_tool: str | None) -> str | None:
    tool = (explicit_tool or '').strip()
    if tool in _VALID_TOOLS:
        return tool
    if message_requests_seven_day_report(message):
        return TOOL_SEVEN_DAY_REPORT
    return detect_symptom_tool(message)


def run_chat_tool(
    tool_name: str,
    *,
    user: User,
    message: str,
    client_behavior: dict[str, Any] | None = None,
) -> str:
    if tool_name == TOOL_SEVEN_DAY_REPORT:
        return build_seven_day_comprehensive_report(user, client_behavior)
    if tool_name == TOOL_SYMPTOM_DIAGNOSTIC:
        return build_symptom_diagnostic_report(user, message, client_behavior)
    raise ValueError(f'Unknown chat tool: {tool_name}')
