from rest_framework import permissions, response, views

from users.services.analytics_dashboard import build_analytics_dashboard
from users.services.behavioral_insights_analytics import (
    build_behaviour_study_day_detail,
    build_content_type_watch_page,
)


class AnalyticsDashboardAPIView(views.APIView):
    """GET /api/auth/analytics/dashboard/?period=day|week|month — full Analytics tab payload."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        period = (request.query_params.get('period') or 'week').strip().lower()
        return response.Response(build_analytics_dashboard(request.user, period))


class BehaviourStudyDayAPIView(views.APIView):
    """GET /api/auth/analytics/behaviour-study/day/ — today only (local midnight window)."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        return response.Response(build_behaviour_study_day_detail(request.user))


class ContentTypeWatchAPIView(views.APIView):
    """GET /api/auth/analytics/content-type/?period=day|week — watched content from video chunks."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        period = (request.query_params.get('period') or 'week').strip().lower()
        if period not in {'day', 'week'}:
            period = 'week'
        return response.Response(build_content_type_watch_page(request.user, period=period))
