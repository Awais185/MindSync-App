from rest_framework import permissions, response, views

from users.services.analytics_dashboard import build_analytics_dashboard


class AnalyticsDashboardAPIView(views.APIView):
    """GET /api/auth/analytics/dashboard/?period=day|week|month — full Analytics tab payload."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        period = (request.query_params.get('period') or 'week').strip().lower()
        return response.Response(build_analytics_dashboard(request.user, period))
