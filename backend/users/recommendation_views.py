from __future__ import annotations

from rest_framework import permissions, response, status, views

from subscriptions.permissions import require_subscription_feature
from users.services.ai_recommendation_engine import get_or_create_ai_wellness_recommendation


class AIWellnessRecommendationAPIView(views.APIView):
    """
    GET /api/auth/recommendations/ai/?refresh=1

    Returns 5–6 line personalized summary from 7-day report data (7-day DB cache).
    """

    permission_classes = (permissions.IsAuthenticated,)

    @require_subscription_feature(
        'personalized_suggestions',
        'Upgrade to Premium to access personalized suggestions',
    )
    def get(self, request):
        force = (request.query_params.get('refresh') or '').strip().lower() in {
            '1',
            'true',
            'yes',
        }
        try:
            payload = get_or_create_ai_wellness_recommendation(
                request.user,
                force_refresh=force,
            )
        except Exception as exc:
            return response.Response(
                {'error': str(exc), 'lines': [], 'summary_text': ''},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        return response.Response(payload, status=status.HTTP_200_OK)
