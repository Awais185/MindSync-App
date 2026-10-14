from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from chat.views import AnalyzeImageAPIView, AnalyzeVideoAPIView
from . import views


urlpatterns = [
    path('admin/', admin.site.urls),
    path('', views.home, name='home'),
    path('api/health/', views.api_health, name='api_health'),
    path('api/public/branding/', views.PublicAppBrandingAPIView.as_view(), name='public_branding'),
    path('api/public/subscription-plans/', views.PublicSubscriptionPlanListAPIView.as_view(), name='public_subscription_plans'),
    path('api/auth/', include('users.urls')),
    path('api/', include('tracking.urls')),
    path('api/', include('subscriptions.urls')),
    path('api/payments/', include('payments.urls')),
    path('api/face/', include('face_detection.urls')),
    path('api/analyze-image/', AnalyzeImageAPIView.as_view(), name='analyze_image'),
    path('api/analyze-video/', AnalyzeVideoAPIView.as_view(), name='analyze_video'),
    path('api/chat/', include('chat.urls')),
    path('api/website/', include('website.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
