"""API for facial expression captures (20s face video → OpenFace AU results)."""

from __future__ import annotations

from django.db.models import Q
from rest_framework import parsers, permissions, response, status, views

from .facial_expression_service import (
    BACKGROUND_SOURCE_TYPES,
    process_facial_expression_capture_sync,
    process_random_incomplete_batch,
    reset_stale_processing_captures,
    submit_facial_expression_processing,
)
from .identity import face_match_score_from_video_path
from .models import FacialExpressionCapture


def _serialize_capture(row: FacialExpressionCapture) -> dict:
    return {
        "id": row.id,
        "user_id": row.user_id,
        "source_type": row.source_type,
        "source_app_name": row.source_app_name,
        "source_package_name": row.source_package_name,
        "duration_seconds": row.duration_seconds,
        "status": row.status,
        "processing_error": row.processing_error,
        "stress_score": row.stress_score,
        "depression_score": row.depression_score,
        "emotion": row.emotion,
        "dominant_state": row.dominant_state,
        "active_aus": row.active_aus or [],
        "au_results": row.au_results,
        "face_match_score": row.face_match_score,
        "mood": row.mood,
        "has_video": bool(row.video),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "processed_at": row.processed_at.isoformat() if row.processed_at else None,
    }


class FaceMoodVideoMatchView(views.APIView):
    """
    POST /api/face/mood-match-video/
    multipart: video (10s face clip). Verifies identity, runs video mood model, saves [FaceMoodScan].
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "video" not in request.data:
            return response.Response(
                {"error": "video file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        import os
        import tempfile

        from users.models import UserProfile

        try:
            profile = UserProfile.objects.get(user=request.user)
        except UserProfile.DoesNotExist:
            return response.Response(
                {"error": "Face not enrolled"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not profile.face_enrolled or not profile.face_image:
            return response.Response(
                {"error": "Face not enrolled"},
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

            score, matched = face_match_score_from_video_path(request.user, tmp_path)
            if not matched:
                return response.Response(
                    {
                        "matched": False,
                        "face_match_score": round(score, 4),
                        "error": "face_identity_mismatch",
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )

            from .mood_scan_service import analyze_video_path, run_video_mood_on_match

            source = (request.data.get("source") or "face_scan_video").strip()[:32]
            persist = source.lower() in {
                "unlock_verify",
                "verify_track",
                "background",
                "unlock",
                "scheduled_background",
            }
            if persist:
                mood = run_video_mood_on_match(
                    request.user,
                    tmp_path,
                    source=source,
                )
            else:
                mood = analyze_video_path(tmp_path)
                return response.Response(
                    {
                        "matched": True,
                        "face_match_score": round(score, 4),
                        "mood_saved": False,
                        "mood": mood,
                        "message": "Video mood prediction complete (not saved).",
                    },
                    status=status.HTTP_200_OK,
                )
            if mood and mood.get("skipped"):
                return response.Response(
                    {
                        "matched": True,
                        "face_match_score": round(score, 4),
                        "mood_saved": False,
                        "mood_skipped": True,
                        "mood_cooldown_seconds": mood.get("cooldown_seconds_remaining", 0),
                        "message": mood.get("message"),
                    },
                    status=status.HTTP_200_OK,
                )
            if not mood:
                return response.Response(
                    {
                        "matched": True,
                        "face_match_score": round(score, 4),
                        "mood_saved": False,
                        "error": "mood_analysis_failed",
                        "message": "Face matched but video mood analysis could not be completed.",
                    },
                    status=status.HTTP_200_OK,
                )
            return response.Response(
                {
                    "matched": True,
                    "face_match_score": round(score, 4),
                    "mood_saved": True,
                    "mood": mood,
                    "mood_message": mood.get(
                        "message",
                        "10s video captured and mood analysis saved.",
                    ),
                },
                status=status.HTTP_200_OK,
            )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass


class FacialExpressionUploadView(views.APIView):
    """
    POST /api/face/expression/upload/
    multipart: video (required), source_type, source_app_name, source_package_name,
               duration_seconds, client_timestamp_ms, verify_face (default true)
    """

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if "video" not in request.data:
            return response.Response(
                {"error": "video file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        source_type = (request.data.get("source_type") or "").strip().lower()
        allowed = {c[0] for c in FacialExpressionCapture.SOURCE_CHOICES}
        if source_type not in allowed:
            source_type = FacialExpressionCapture.SOURCE_VIDEO_WATCH
        recording_type = (request.data.get("recording_type") or "face_camera").strip()[:32]
        if (
            source_type == FacialExpressionCapture.SOURCE_MANUAL
            or recording_type in {"manual_scan", "face_scan", "user_session"}
        ):
            return response.Response(
                {
                    "error": "manual_scan_not_persisted",
                    "message": (
                        "Manual face scans are preview-only. Background scheduled "
                        "captures are saved automatically."
                    ),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        if source_type not in BACKGROUND_SOURCE_TYPES:
            source_type = FacialExpressionCapture.SOURCE_VIDEO_WATCH

        try:
            duration_seconds = int(request.data.get("duration_seconds") or 20)
        except (TypeError, ValueError):
            duration_seconds = 20
        duration_seconds = max(1, min(120, duration_seconds))

        client_ts = request.data.get("client_timestamp_ms")
        try:
            client_timestamp_ms = int(client_ts) if client_ts is not None else None
        except (TypeError, ValueError):
            client_timestamp_ms = None

        identity_preverified = str(
            request.data.get("identity_preverified") or "false"
        ).lower() in {"1", "true", "yes"}
        verify_face = str(request.data.get("verify_face") or "false").lower() in {
            "1",
            "true",
            "yes",
        }
        if identity_preverified:
            verify_face = False
        run_mood_scan = str(request.data.get("run_mood_scan") or "false").lower() in {
            "1",
            "true",
            "yes",
        }
        # Facial Expression Detection uploads must never trigger Face Mood Scan.
        if recording_type == "facial_expression_detection":
            run_mood_scan = False

        import os
        import tempfile

        tmp_path = None
        face_score = None
        capture: FacialExpressionCapture | None = None
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

            mood_payload = None
            if identity_preverified:
                face_score = 1.0
            elif verify_face:
                from .identity import face_match_score_from_video_path_multi

                score, matched = face_match_score_from_video_path_multi(
                    request.user,
                    tmp_path,
                    max_frames=6,
                    unlock_capture=True,
                )
                face_score = score
                if not matched:
                    return response.Response(
                        {
                            "error": "face_identity_mismatch",
                            "face_match_score": round(score, 4),
                        },
                        status=status.HTTP_403_FORBIDDEN,
                    )
                if run_mood_scan:
                    try:
                        from .mood_scan_service import run_video_mood_on_match

                        mood_payload = run_video_mood_on_match(
                            request.user,
                            tmp_path,
                            source="expression_upload",
                        )
                    except Exception:
                        mood_payload = None

            session_id = (request.data.get("session_id") or "").strip()[:64]
            device_id = (request.data.get("device_id") or "").strip()[:128]
            capture = FacialExpressionCapture(
                user=request.user,
                source_type=source_type,
                source_app_name=(request.data.get("source_app_name") or "")[:120],
                source_package_name=(request.data.get("source_package_name") or "")[:200],
                duration_seconds=duration_seconds,
                face_match_score=face_score,
                mood=mood_payload,
                client_timestamp_ms=client_timestamp_ms,
                status=FacialExpressionCapture.STATUS_PENDING,
                au_results={
                    "capture_meta": {
                        "session_id": session_id,
                        "device_id": device_id,
                        "recording_type": recording_type,
                        "captured_at": client_timestamp_ms,
                    }
                },
            )
            capture.save()

            with open(tmp_path, "rb") as src:
                capture.video.save(
                    os.path.basename(tmp_path),
                    src,
                    save=True,
                )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass

        if capture is None:
            return response.Response(
                {"error": "upload_failed"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        submit_facial_expression_processing(capture.id)
        print(
            f"Facial expression video saved to database — user={request.user.id} "
            f"capture_id={capture.id} app={capture.source_app_name!r}",
            flush=True,
        )
        return response.Response(
            {
                "ok": True,
                "id": capture.id,
                "status": capture.status,
                "status_url": f"/api/face/expression/{capture.id}/",
            },
            status=status.HTTP_201_CREATED,
        )


class FacialExpressionDetailView(views.APIView):
    """GET /api/face/expression/<id>/"""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request, capture_id: int):
        row = FacialExpressionCapture.objects.filter(
            id=capture_id,
            user=request.user,
        ).first()
        if row is None:
            return response.Response({"error": "not_found"}, status=status.HTTP_404_NOT_FOUND)
        return response.Response(_serialize_capture(row))


class FacialExpressionListView(views.APIView):
    """GET /api/face/expression/ — recent captures for the logged-in user."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        limit = min(50, max(1, int(request.query_params.get("limit", 20))))
        rows = FacialExpressionCapture.objects.filter(user=request.user).order_by("-created_at")[:limit]
        return response.Response(
            {
                "count": len(rows),
                "results": [_serialize_capture(r) for r in rows],
            }
        )


class FacialExpressionRecoverView(views.APIView):
    """
    POST /api/face/expression/recover/
    Body: { "limit": 5, "random": true }
    Re-processes captures that have video but missing/failed OpenFace results.
    """

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        try:
            limit = int(request.data.get("limit") or 5)
        except (TypeError, ValueError):
            limit = 5
        limit = max(1, min(limit, 15 if request.user.is_staff else 5))
        random_order = str(request.data.get("random", "true")).lower() not in {"0", "false", "no"}
        reset_stale_processing_captures()
        processed = process_random_incomplete_batch(limit=limit, random_order=random_order)
        return response.Response({"ok": True, "processed": processed, "reset_stale": True})


class FacialExpressionReprocessView(views.APIView):
    """POST /api/face/expression/<id>/reprocess/ — owner can retry OpenFace on their capture."""

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request, capture_id: int):
        row = FacialExpressionCapture.objects.filter(
            id=capture_id,
            user=request.user,
        ).first()
        if row is None:
            return response.Response({"error": "not_found"}, status=status.HTTP_404_NOT_FOUND)
        if not row.video:
            return response.Response(
                {"error": "video_not_available"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        ok = process_facial_expression_capture_sync(row.id)
        row.refresh_from_db()
        return response.Response(
            {
                "ok": ok,
                "capture": _serialize_capture(row),
            },
            status=status.HTTP_200_OK if ok else status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
