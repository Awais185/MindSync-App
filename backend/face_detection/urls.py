from django.urls import path
from .face_chunk_views import FaceChunkUploadView
from .mood_detect_views import FaceMoodDetectImageView, FaceMoodDetectVideoView
from .expression_views import (
    FaceMoodVideoMatchView,
    FacialExpressionDetailView,
    FacialExpressionListView,
    FacialExpressionRecoverView,
    FacialExpressionReprocessView,
    FacialExpressionUploadView,
)
from .views import (
    FaceEmotionDetectionView,
    FaceEmotionVideoView,
    FaceBehaviorAnalyzeView,
    FaceBehaviorWarmupView,
    FaceBehaviorLatestView,
    FaceVerifyAndTrackView,
    ScreenTimeStatsView,
)

urlpatterns = [
    path("detect/", FaceEmotionDetectionView.as_view(), name="face_detect"),
    path("detect-video/", FaceEmotionVideoView.as_view(), name="face_detect_video"),
    path("behavior/analyze/", FaceBehaviorAnalyzeView.as_view(), name="face_behavior_analyze"),
    path("behavior/warmup/", FaceBehaviorWarmupView.as_view(), name="face_behavior_warmup"),
    path("behavior/latest/", FaceBehaviorLatestView.as_view(), name="face_behavior_latest"),
    path("verify-track/", FaceVerifyAndTrackView.as_view(), name="face_verify_track"),
    path("mood-detect/image/", FaceMoodDetectImageView.as_view(), name="face_mood_detect_image"),
    path("mood-detect/video/", FaceMoodDetectVideoView.as_view(), name="face_mood_detect_video"),
    path("mood-match-video/", FaceMoodVideoMatchView.as_view(), name="face_mood_match_video"),
    path("stats/", ScreenTimeStatsView.as_view(), name="screentime_stats"),
    path("chunk/", FaceChunkUploadView.as_view(), name="face_chunk_upload"),
    path("expression/upload/", FacialExpressionUploadView.as_view(), name="facial_expression_upload"),
    path("expression/recover/", FacialExpressionRecoverView.as_view(), name="facial_expression_recover"),
    path("expression/", FacialExpressionListView.as_view(), name="facial_expression_list"),
    path(
        "expression/<int:capture_id>/reprocess/",
        FacialExpressionReprocessView.as_view(),
        name="facial_expression_reprocess",
    ),
    path(
        "expression/<int:capture_id>/",
        FacialExpressionDetailView.as_view(),
        name="facial_expression_detail",
    ),
]
