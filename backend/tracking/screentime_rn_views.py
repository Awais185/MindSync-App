"""Screen time save-day + weekly/monthly rollups."""

from __future__ import annotations

from datetime import date

from django.utils import timezone
from rest_framework import permissions, response, status, views

from .services.screentime_rollup import (
    maybe_reset_monthly_after_30_days,
    maybe_roll_weekly_to_monthly,
    roll_completed_day_into_weekly,
    summary_for_user,
    sync_screen_time_seconds_row,
)


class ScreenTimeSaveDayView(views.APIView):
    """POST /api/screentime/save-day/  body: { total_ms, date? }"""

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        try:
            total_ms = int(request.data.get('total_ms') or 0)
        except (TypeError, ValueError):
            return response.Response({'error': 'total_ms required'}, status=status.HTTP_400_BAD_REQUEST)

        raw_date = request.data.get('date')
        if raw_date:
            day = date.fromisoformat(str(raw_date)[:10])
        else:
            day = timezone.now().date()

        user = request.user
        roll_completed_day_into_weekly(user, day, total_ms)
        rolled_week = maybe_roll_weekly_to_monthly(user, timezone.now().date())
        rolled_month = maybe_reset_monthly_after_30_days(user, timezone.now().date())
        sync_screen_time_seconds_row(user, total_seconds=total_ms // 1000, day=day)

        return response.Response(
            {
                'ok': True,
                'date': day.isoformat(),
                'total_ms': max(0, total_ms),
                'rolled_week': rolled_week,
                'rolled_month': rolled_month,
                'summary': summary_for_user(user),
            }
        )
