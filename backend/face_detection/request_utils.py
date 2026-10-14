"""Helpers for large multipart uploads from mobile clients."""

from __future__ import annotations

import logging

from django.http.request import UnreadablePostError
from rest_framework import response, status

logger = logging.getLogger(__name__)


def client_disconnected_response(*, endpoint: str = ""):
    label = f" ({endpoint})" if endpoint else ""
    logger.info(
        "Upload interrupted%s — client closed connection before body finished",
        label,
    )
    return response.Response(
        {
            "error": "upload_interrupted",
            "detail": "Upload was cancelled or timed out before the server received the full file. Please retry.",
            "retry": True,
        },
        status=status.HTTP_400_BAD_REQUEST,
    )


def get_multipart_data(request, *, endpoint: str = ""):
    """
    Access request.data / request.FILES; return a 400 response dict instead of raising 500
    when the phone drops the connection mid-upload.
    """
    try:
        return request.data, None
    except UnreadablePostError:
        return None, client_disconnected_response(endpoint=endpoint)
