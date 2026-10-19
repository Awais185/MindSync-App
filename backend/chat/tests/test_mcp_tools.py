from django.contrib.auth.models import User
from django.test import TestCase

from chat.mcp.guardrails import (
    is_likely_off_topic,
    message_requests_seven_day_report,
)
from chat.mcp.router import (
    TOOL_SEVEN_DAY_REPORT,
    TOOL_SYMPTOM_DIAGNOSTIC,
    resolve_requested_tool,
    run_chat_tool,
)


class McpGuardrailsTests(TestCase):
    def test_my_report_triggers_seven_day_tool(self):
        self.assertTrue(message_requests_seven_day_report('My Report'))
        self.assertEqual(
            resolve_requested_tool('My Report', None),
            TOOL_SEVEN_DAY_REPORT,
        )

    def test_explicit_tool_wins(self):
        self.assertEqual(
            resolve_requested_tool('hello', TOOL_SEVEN_DAY_REPORT),
            TOOL_SEVEN_DAY_REPORT,
        )

    def test_symptom_detection(self):
        self.assertEqual(
            resolve_requested_tool('I have a bad headache today', None),
            TOOL_SYMPTOM_DIAGNOSTIC,
        )

    def test_off_topic_heuristic(self):
        self.assertTrue(
            is_likely_off_topic('Can you write python code to sort a list?'),
        )
        self.assertFalse(is_likely_off_topic('I feel stressed about screen time'))


class McpReportToolTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='mcp_user', password='test-pass-123')

    def test_seven_day_report_header(self):
        text = run_chat_tool(
            TOOL_SEVEN_DAY_REPORT,
            user=self.user,
            message='My Report',
            client_behavior=None,
        )
        self.assertIn('## Your 7-day MindSync wellness report', text)

    def test_symptom_report_mentions_screen_time(self):
        text = run_chat_tool(
            TOOL_SYMPTOM_DIAGNOSTIC,
            user=self.user,
            message='My eyes hurt from my phone',
            client_behavior=None,
        )
        self.assertIn('24 hours', text.lower())
