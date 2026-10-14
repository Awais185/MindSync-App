from django.urls import path

from .chunk_screen_views import ScreenChunkUploadView
from .screentime_rn_views import ScreenTimeSaveDayView
from .screentime_summary_views import ScreenTimeSummaryView
from .views import (
    BehavioralAnalyticsView,
    FaceVerifyView,
    FaceVerificationAnalyticsView,
    FaceVerificationEventView,
    ScreenTimeTodayView,
    ScreenTimeUpdateView,
    VideoUploadStatusView,
    VideoUploadView,
    WeeklyReportView,
)
from .recommendations_views import RecommendationsAPIView

# Mounted at prefix /api/ — see backend/urls.py
urlpatterns = [
    path('screentime/save-day/', ScreenTimeSaveDayView.as_view(), name='screentime_save_day'),
    path('screentime/summary/', ScreenTimeSummaryView.as_view(), name='screentime_summary'),
    path('chunks/screen/', ScreenChunkUploadView.as_view(), name='chunks_screen'),
    path('video/upload/', VideoUploadView.as_view(), name='video_upload'),
    path('video/upload/<int:clip_id>/', VideoUploadStatusView.as_view(), name='video_upload_status'),
    path('screen-time/update/', ScreenTimeUpdateView.as_view(), name='screen_time_update'),
    path('screen-time/today/', ScreenTimeTodayView.as_view(), name='screen_time_today'),
    path('face-verify/', FaceVerifyView.as_view(), name='face_verify'),
    path(
        'face-verification/events/',
        FaceVerificationEventView.as_view(),
        name='face_verification_event',
    ),
    path(
        'face-verification/analytics/',
        FaceVerificationAnalyticsView.as_view(),
        name='face_verification_analytics',
    ),
    path(
        'analytics/behavioral/',
        BehavioralAnalyticsView.as_view(),
        name='behavioral_analytics',
    ),
    path('reports/weekly/', WeeklyReportView.as_view(), name='weekly_report'),
    path('recommendations/', RecommendationsAPIView.as_view(), name='recommendations'),
]
