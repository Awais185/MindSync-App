"""Live mood weekly API and archived weekly reports."""

from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from users.services.mood_weekly_service import (
    build_weekly_mood_payload,
    get_archived_report,
    list_past_weekly_reports,
    maybe_archive_mood_window,
)
from users.services.weekly_report_builder import build_and_save_weekly_report


class WeeklyMoodLiveAPIView(APIView):
    """Home page weekly mood architecture (poll for live updates)."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        maybe_archive_mood_window(request.user)
        payload = build_weekly_mood_payload(request.user, request=request)
        return Response(payload)


class MoodInsightsLiveAPIView(APIView):
    """Mental health insights from current mood window."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        maybe_archive_mood_window(request.user)
        payload = build_weekly_mood_payload(request.user, request=request)
        return Response({'insights': payload.get('insights'), 'window': {
            'window_start': payload.get('window_start'),
            'window_end': payload.get('window_end'),
            'entry_count': payload.get('entry_count'),
            'dominant_mood': payload.get('dominant_mood'),
        }})


class PastWeeklyReportsAPIView(APIView):
    """List archived 7-day reports."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        return Response({'results': list_past_weekly_reports(request.user)})


class ArchivedWeeklyReportDetailAPIView(APIView):
    """Fetch one archived report for PDF export."""

    permission_classes = (IsAuthenticated,)

    def get(self, request, report_id: int):
        row = get_archived_report(request.user, report_id)
        if row is None:
            return Response({'detail': 'Report not found.'}, status=status.HTTP_404_NOT_FOUND)
        payload = row.payload if isinstance(row.payload, dict) else {}
        from users.services.seven_day_report_studio import build_studio_report

        studio = build_studio_report(
            request.user,
            payload,
            past_reports=[],
            clinical_summary=None,
        )
        return Response(
            {
                'id': row.id,
                'week_start': row.week_start.isoformat(),
                'week_end': row.week_end.isoformat(),
                'generated_at': row.generated_at.isoformat(),
                'report': payload,
                'studio': studio,
            }
        )


class LiveUserWeeklyReportAPIView(APIView):
    """GET current rolling 7-day report JSON (updates daily as data arrives)."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        maybe_archive_mood_window(request.user)
        row = build_and_save_weekly_report(request.user)
        payload = row.payload or {}
        mood = build_weekly_mood_payload(request.user, request=request)
        if isinstance(payload, dict):
            payload = dict(payload)
            payload['mood_weekly'] = mood
        from users.services.mood_weekly_service import list_past_weekly_reports
        from users.services.seven_day_report_studio import build_studio_report
        from users.wellbeing import build_weekly_report_text

        past = list_past_weekly_reports(request.user)
        summary_text = build_weekly_report_text(request.user, days=7)
        studio = build_studio_report(
            request.user,
            payload if isinstance(payload, dict) else {},
            mood_weekly=mood,
            past_reports=past,
            clinical_summary=summary_text,
        )
        return Response(
            {
                'week_start': row.week_start.isoformat(),
                'week_end': row.week_end.isoformat(),
                'generated_at': row.generated_at.isoformat(),
                'report': payload,
                'mood_weekly': mood,
                'studio': studio,
            }
        )
