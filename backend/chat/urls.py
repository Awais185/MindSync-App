"""
Chat HTTP routes under /api/chat/.

Mood scan endpoints are registered at project root as:
  POST /api/analyze-image/
  POST /api/analyze-video/
(see backend/urls.py).
"""
from django.urls import path

from .views import (
    ChatAPIView,
    ChatHistoryAPIView,
    ChatSessionListCreateAPIView,
    ChatSessionDeleteAPIView,
    ChatSessionMessagesAPIView,
    MentalStateAPIView,
    OpenRouterProxyAPIView,
)

urlpatterns = [
    path('', ChatAPIView.as_view(), name='chat'),
    path('history/', ChatHistoryAPIView.as_view(), name='chat-history'),
    path('sessions/', ChatSessionListCreateAPIView.as_view(), name='chat-sessions'),
    path('sessions/<int:session_id>/', ChatSessionDeleteAPIView.as_view(), name='chat-session-delete'),
    path('sessions/<int:session_id>/messages/', ChatSessionMessagesAPIView.as_view(), name='chat-session-messages'),
    path('openrouter/', OpenRouterProxyAPIView.as_view(), name='chat-openrouter'),
    path('mental-state/', MentalStateAPIView.as_view(), name='chat-mental-state'),
]
