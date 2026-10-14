from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import AppBranding, SubscriptionPlan
from users.serializers import AppBrandingSerializer, SubscriptionPlanSerializer


def home(request):
    return render(request, 'home.html')


def api_health(request):
    """GET /api/health/ — quick check that Django is up and chat URL is correct."""
    return JsonResponse(
        {
            "ok": True,
            "service": "MindSync API",
            "post_chat": "/api/chat/",
            "get_health": "/api/health/",
            "note": "Chat requires Authorization: Bearer <access_token> and JSON body {\"message\": \"...\"}",
        }
    )


class PublicAppBrandingAPIView(APIView):
    permission_classes = (AllowAny,)

    def get(self, request):
        branding = AppBranding.objects.order_by('id').first()
        if branding is None:
            return Response(
                {
                    'app_name': 'MindSync',
                    'welcome_tagline': 'AI-Powered Emotional Wellness',
                    'logo_url': '',
                    'updated_at': None,
                }
            )
        return Response(AppBrandingSerializer(branding, context={'request': request}).data)


class PublicSubscriptionPlanListAPIView(APIView):
    permission_classes = (AllowAny,)

    def get(self, request):
        plans = SubscriptionPlan.objects.filter(is_active=True).order_by('sort_order', 'id')
        return Response({'results': SubscriptionPlanSerializer(plans, many=True).data})
