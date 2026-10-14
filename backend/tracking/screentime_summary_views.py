"""Unified screen time totals for Flutter (single source of truth)."""

from rest_framework import permissions, response, views

from .services.screentime_rollup import summary_for_user


class ScreenTimeSummaryView(views.APIView):
    """GET /api/screentime/summary/ — today / week / month totals (ms + seconds)."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        return response.Response(summary_for_user(request.user))
