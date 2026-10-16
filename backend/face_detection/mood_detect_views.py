"""Manual face-scan UI — inference only; never writes to the database."""

from __future__ import annotations

import os
import tempfile

from rest_framework import parsers, permissions, response, status, views

from .dual_model_service import analyze_manual_image, analyze_manual_video


class FaceMoodDetectImageView(views.APIView):
    """
    POST /api/face/mood-detect/image/
    multipart: image — emotion + depression (OpenFace); not persisted.
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        upload = request.FILES.get("image") or request.data.get("image")
        if upload is None:
            return response.Response(
                {"error": "image file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            image_bytes = upload.read()
            if not image_bytes:
                return response.Response(
                    {"error": "empty_image"},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            dual = analyze_manual_image(image_bytes)
            return response.Response(
                {
                    "mood_saved": False,
                    "mood": dual.get("mood"),
                    "depression": dual.get("depression"),
                    "identity_check": "manual_ui_not_saved",
                    "message": "Emotion and depression analysis complete (not saved).",
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
    multipart: video — emotion + depression; not saved.
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        video_file = request.FILES.get("video") or request.data.get("video")
        if video_file is None:
            return response.Response(
                {"error": "video file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tmp_path = None
        try:
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

            dual = analyze_manual_video(tmp_path)
            return response.Response(
                {
                    "mood_saved": False,
                    "mood": dual.get("mood"),
                    "depression": dual.get("depression"),
                    "identity_check": "skipped_ui_demo",
                    "message": "Video emotion and depression analysis complete.",
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
