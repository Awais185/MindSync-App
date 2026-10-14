"""UI mood detection — no face ownership check (background monitoring unchanged)."""

from __future__ import annotations

import os
import tempfile

from rest_framework import parsers, permissions, response, status, views

from .mood_scan_service import analyze_image_bytes, analyze_video_path


class FaceMoodDetectImageView(views.APIView):
    """
    POST /api/face/mood-detect/image/
    multipart: image — predicts mood for any face (no identity verification).
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "image" not in request.data:
            return response.Response(
                {"error": "image file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            image_bytes = request.data["image"].read()
            mood = analyze_image_bytes(image_bytes)
            return response.Response(
                {
                    "mood_saved": False,
                    "mood": mood,
                    "identity_check": "skipped_ui_demo",
                    "message": "Mood prediction complete.",
                },
                status=status.HTTP_200_OK,
            )
        except Exception as exc:
            return response.Response(
                {"error": "mood_analysis_failed", "detail": str(exc)[:500]},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class FaceMoodDetectVideoView(views.APIView):
    """
    POST /api/face/mood-detect/video/
    multipart: video — predicts mood for any face (no identity verification).
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "video" not in request.data:
            return response.Response(
                {"error": "video file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tmp_path = None
        try:
            video_file = request.data["video"]
            suffix = ".mp4"
            name = getattr(video_file, "name", "") or ""
            lower = name.lower()
            if lower.endswith(".mov"):
                suffix = ".mov"
            elif lower.endswith(".webm"):
                suffix = ".webm"

            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                for chunk in video_file.chunks():
                    tmp.write(chunk)
                tmp_path = tmp.name

            mood = analyze_video_path(tmp_path)
            return response.Response(
                {
                    "mood_saved": False,
                    "mood": mood,
                    "identity_check": "skipped_ui_demo",
                    "message": "Video mood prediction complete.",
                },
                status=status.HTTP_200_OK,
            )
        except Exception as exc:
            return response.Response(
                {"error": "mood_analysis_failed", "detail": str(exc)[:500]},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
