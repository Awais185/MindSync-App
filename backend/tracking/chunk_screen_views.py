"""POST /api/chunks/screen/ — 30s screen chunk → script + classification + behavior."""

from rest_framework import parsers, permissions

from .views import VideoUploadView


class ScreenChunkUploadView(VideoUploadView):
    """
    Same pipeline as /api/video/upload/ (VideoClip + VideoChunkAnalysis).
    Alias for React Native screen recorder uploads.
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)
