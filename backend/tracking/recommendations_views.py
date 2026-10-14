from __future__ import annotations

from rest_framework import permissions, response, status
from rest_framework.views import APIView

from .recommendations_engine import build_recommendations
from subscriptions.permissions import require_subscription_feature


class RecommendationsAPIView(APIView):
    """
    GET /api/recommendations/?range=day|week|month

    Returns AI/logic-based personalized recommendations as dynamic cards.
    """

    permission_classes = (permissions.IsAuthenticated,)

    @require_subscription_feature(
        'personalized_suggestions',
        'Upgrade to Premium to access personalized suggestions',
    )
    def get(self, request):
        selected = (request.query_params.get("range") or "week").strip().lower()
        if selected not in {"day", "week", "month"}:
            selected = "week"

        try:
            cards = build_recommendations(request.user, range_key=selected)
        except Exception as exc:
            return response.Response(
                {
                    "range": selected,
                    "recommendations": [],
                    "error": str(exc),
                },
                status=status.HTTP_200_OK,
            )

        return response.Response(
            {
                "range": selected,
                "recommendations": cards,
            },
            status=status.HTTP_200_OK,
        )

