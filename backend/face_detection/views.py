import logging
import os
import tempfile
import time

from django.conf import settings
from django.core.files.base import ContentFile
from django.utils import timezone
from PIL import Image
from rest_framework import parsers, permissions, response, status, views

from tracking.models import ScreenTimeSession

from chat.video_model import analyze_video_file_path as chat_analyze_video_file_path

from .emotion_models import predict_image_pil, predict_video_path
from .emotion_score_fallback import merge_emotion_fallback, openface_results_weak
from .face_verification_service import DEFAULT_THRESHOLD
from .profile_face_verify import verify_probe_for_user
from .models import FaceSnapshot, MentalHealthResult
from subscriptions.constants import PLAN_FREE
from subscriptions.services import SubscriptionService
from subscriptions.permissions import require_subscription_feature

logger = logging.getLogger(__name__)
from .openface_pipeline import (
    OpenFaceAnalysisResult,
    _count_readable_frames,
    _safe_unlink,
    default_snapshot_expiry,
    extract_snapshots,
    prepare_unified_analysis_video,
    run_openface_and_analyze,
)
from .request_utils import get_multipart_data


class FaceEmotionDetectionView(views.APIView):
    """POST multipart field `image` — returns [{label, score}, ...] (local transformers pipeline)."""

    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request, *args, **kwargs):
        if "image" not in request.data:
            return response.Response({"error": "No image provided"}, status=status.HTTP_400_BAD_REQUEST)

        image_file = request.data["image"]
        try:
            with Image.open(image_file) as img:
                img = img.convert("RGB")
                out = predict_image_pil(img)
            return response.Response(out, status=status.HTTP_200_OK)
        except Exception as e:
            return response.Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class FaceEmotionVideoView(views.APIView):
    """POST multipart field `video` — analyzes sampled frames; returns summary + per-frame top labels."""

    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request, *args, **kwargs):
        if "video" not in request.data:
            return response.Response({"error": "No video provided"}, status=status.HTTP_400_BAD_REQUEST)

        video_file = request.data["video"]
        suffix = ".mp4"
        name = getattr(video_file, "name", "") or ""
        lower = name.lower()
        if lower.endswith(".mov"):
            suffix = ".mov"
        elif lower.endswith(".webm"):
            suffix = ".webm"

        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                for chunk in video_file.chunks():
                    tmp.write(chunk)
                tmp_path = tmp.name

            max_frames = getattr(settings, "EMOTION_VIDEO_MAX_FRAMES", 120)
            result = predict_video_path(tmp_path, max_frames=max_frames)
            if result.get("error"):
                return response.Response(result, status=status.HTTP_400_BAD_REQUEST)
            return response.Response(result, status=status.HTTP_200_OK)
        except Exception as e:
            return response.Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass


class FaceVerifyAndTrackView(views.APIView):
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        user = request.user

        data, disconnect = get_multipart_data(request, endpoint="verify-track")
        if disconnect is not None:
            return disconnect

        if "image" not in data:
            return response.Response({"error": "No image provided"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            from users.models import UserProfile

            profile, _ = UserProfile.objects.get_or_create(
                user=user,
                defaults={"profession": "other", "face_enrolled": False},
            )
            if not profile.face_image:
                logger.warning(
                    "verify-track: user_id=%s username=%s — no face_image on profile "
                    "(face_enrolled=%s). Re-enroll face in the app.",
                    user.id,
                    user.username,
                    profile.face_enrolled,
                )
                return response.Response(
                    {
                        "matched": False,
                        "match": False,
                        "status": "not_enrolled",
                        "error": "Face not enrolled",
                        "detail": "Enroll your face in MindSync settings, then unlock again.",
                    },
                    status=status.HTTP_200_OK,
                )

            uploaded = data["image"].read()
            unlock_capture = str(
                data.get("source") or data.get("capture_context") or ""
            ).strip().lower() in {"unlock", "background", "unlock_verify"}

            raw_thr = data.get("match_threshold") or os.environ.get(
                "FACE_VERIFY_TRACK_THRESHOLD",
                os.environ.get("FACE_MATCH_THRESHOLD", str(DEFAULT_THRESHOLD)),
            )
            try:
                threshold = float(raw_thr)
            except (TypeError, ValueError):
                threshold = DEFAULT_THRESHOLD

            _, result = verify_probe_for_user(
                user,
                uploaded,
                threshold=threshold,
                unlock_capture=unlock_capture,
            )

            face_size_pct = float(result.get("face_area_percent") or 0.0)
            matched = bool(result.get("matched"))
            probability = float(result.get("probability") or 0.0)
            distance = float(result.get("distance") or 1.0)

            if result.get("status") == "rejected":
                reason_key = str(result.get("reject_reason") or "rejected").lower()
                msg = f"NO MATCH | confidence:0.0 | reason:{reason_key}"
                logger.info("[MindSync] %s", msg)
                print(f"[MindSync] {msg}", flush=True)
                return response.Response(result, status=status.HTTP_200_OK)

            if matched:
                today = timezone.now().date()
                ScreenTimeSession.objects.get_or_create(
                    user=user,
                    date=today,
                    defaults={"total_ms": 0},
                )
                mood_payload = None
                try:
                    from .mood_scan_service import run_image_mood_on_match

                    mood_payload = run_image_mood_on_match(
                        user,
                        uploaded,
                        source="verify_track",
                    )
                except Exception as mood_exc:
                    logger.warning("Mood scan after match failed: %s", mood_exc)
                result = dict(result)
                if mood_payload and mood_payload.get("skipped"):
                    result["mood_saved"] = False
                    result["mood_skipped"] = True
                    result["mood_cooldown_seconds"] = mood_payload.get(
                        "cooldown_seconds_remaining", 0
                    )
                    result["mood_message"] = mood_payload.get(
                        "message",
                        "Face matched. Mood scan is on a 5-minute pause.",
                    )
                elif mood_payload and not mood_payload.get("skipped"):
                    result["mood"] = mood_payload
                    result["mood_saved"] = True
                    result["mood_message"] = mood_payload.get(
                        "message",
                        "Photo captured and mood analysis saved.",
                    )
                else:
                    result["mood_saved"] = False
                    result["mood_message"] = (
                        "Face matched. Mood analysis is temporarily unavailable — try again shortly."
                    )
                msg = (
                    f"MATCH ✓ | probability:{probability:.3f} | distance:{distance:.3f} | "
                    f"face_size:{face_size_pct:.1f}% (threshold={threshold:.2f})"
                )
                logger.info("[MindSync] %s", msg)
                print(f"[MindSync] {msg}", flush=True)
                return response.Response(result, status=status.HTTP_200_OK)

            msg = (
                f"NO MATCH | probability:{probability:.3f} | distance:{distance:.3f} | "
                f"reason:below_threshold"
            )
            logger.info("[MindSync] %s", msg)
            print(f"[MindSync] {msg}", flush=True)
            return response.Response(result, status=status.HTTP_200_OK)

        except Exception as e:
            return response.Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class ScreenTimeStatsView(views.APIView):
    """Placeholder until DailyUsage / ScreenTimeSession models are wired."""

    def get(self, request):
        user = request.user
        if not user.is_authenticated:
            return response.Response({"error": "Authentication required"}, status=status.HTTP_401_UNAUTHORIZED)

        return response.Response(
            {
                "total_time": "0h 0m",
                "social_time": "0h 0m",
                "apps": [],
                "note": "Aggregate screen-time stats are not configured on this server build.",
            }
        )


class FaceBehaviorAnalyzeView(views.APIView):
    """
    POST /api/face/behavior/analyze/

    multipart:
      - video: 30s face video (temporary; deleted after processing)
      - source_type: unlock|screen_on|video_watch|random_usage

    Returns final mental-health scores + behavior insights and creates expiring peak snapshots.
    """

    parser_classes = (parsers.MultiPartParser, parsers.FormParser)
    permission_classes = (permissions.IsAuthenticated,)

    @require_subscription_feature(
        'emotion_detection_full',
        'Upgrade to Premium to access Deep Face Analysis.',
    )
    def post(self, request, *args, **kwargs):
        plan_code = SubscriptionService.current_plan_code(request.user)
        if plan_code == PLAN_FREE:
            return response.Response(
                {
                    "message": "Upgrade your plan to access this feature.",
                    "detail": "Free plan does not include emotion scan access.",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        data, disconnect = get_multipart_data(request, endpoint="behavior/analyze")
        if disconnect is not None:
            return disconnect

        if "video" not in data:
            return response.Response(
                {"error": "video file is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        source_type = (data.get("source_type") or "").strip().lower()
        allowed = {
            MentalHealthResult.SOURCE_UNLOCK,
            MentalHealthResult.SOURCE_SCREEN_ON,
            MentalHealthResult.SOURCE_VIDEO_WATCH,
            MentalHealthResult.SOURCE_RANDOM_USAGE,
        }
        if source_type not in allowed:
            source_type = MentalHealthResult.SOURCE_RANDOM_USAGE

        video_file = data["video"]
        suffix = ".mp4"
        name = getattr(video_file, "name", "") or ""
        lower = name.lower()
        allowed_exts = {".mp4", ".mov", ".webm", ".avi", ".mkv"}
        ext = os.path.splitext(lower)[1] if "." in lower else ".mp4"
        # Do not reject unknown camera temp names; treat them as mp4-compatible uploads.
        if ext and ext not in allowed_exts:
            ext = ".mp4"
        if lower.endswith(".mov"):
            suffix = ".mov"
        elif lower.endswith(".webm"):
            suffix = ".webm"
        elif lower.endswith(".avi"):
            suffix = ".avi"
        elif lower.endswith(".mkv"):
            suffix = ".mkv"
        elif ext == ".mp4":
            suffix = ".mp4"

        scan_type = (data.get("scan_type") or "").strip().lower()
        if scan_type not in {"recorded", "uploaded"}:
            scan_type = "recorded"
        include_media = str(data.get("include_media") or "true").strip().lower() not in {
            "0",
            "false",
            "no",
        }
        include_deepface = str(data.get("include_deepface_results") or "true").strip().lower() not in {
            "0",
            "false",
            "no",
        }
        fast_mode = str(data.get("fast_mode") or "true").strip().lower() not in {
            "0",
            "false",
            "no",
        }

        source_app_name = (data.get("source_app_name") or "").strip()[:120]
        source_package_name = (data.get("source_package_name") or "").strip()[:200]

        tmp_path = None
        prepared_path = None
        prepared_duration = 0.0
        started_at = time.perf_counter()
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                for chunk in video_file.chunks():
                    tmp.write(chunk)
                tmp_path = tmp.name

            upload_size = os.path.getsize(tmp_path)
            if upload_size < 12_000:
                return response.Response(
                    {
                        "error": "video_too_small",
                        "detail": (
                            "Uploaded video is empty or incomplete. "
                            "Record again and wait for preview before analyzing."
                        ),
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if _count_readable_frames(tmp_path) < 2:
                return response.Response(
                    {
                        "error": "video_unreadable",
                        "detail": (
                            "Server could not read frames from this video. "
                            "Use Record From Camera, wait for playback preview, then analyze."
                        ),
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            # Unified preprocessing for camera + gallery upload (same FFmpeg-first path).
            prepared_path, prepared_duration = prepare_unified_analysis_video(
                tmp_path,
                fast_mode=True,
            )
            logger.info(
                "behavior/analyze pipeline user=%s scan_type=%s fast_mode=%s "
                "prepared=%s duration=%.2fs decoded_in=%s decoded_out=%s",
                request.user.id,
                scan_type,
                fast_mode,
                prepared_path,
                prepared_duration,
                _count_readable_frames(tmp_path),
                _count_readable_frames(prepared_path),
            )

            from .analysis_warmup import ensure_behavior_models_warm
            from .openface_pipeline import is_openface_available
            from .video_au_tracker import run_cross_platform_video_analysis

            # Same AU → stress/anxiety/depression math as OpenFace CSV; tuned for <40s total.
            pipeline_fast = True
            warmup_status = ensure_behavior_models_warm()

            openface_host = is_openface_available()
            if openface_host:
                analysis = run_openface_and_analyze(
                    input_video_path=prepared_path,
                    max_peak_frames=3,
                    include_tracked_video=include_media,
                    fast_mode=pipeline_fast,
                    prepared_video_path=prepared_path,
                )
            else:
                logger.info(
                    "behavior/analyze: AU video tracker (user=%s) warmup=%s",
                    request.user.id,
                    warmup_status,
                )
                analysis = run_cross_platform_video_analysis(
                    prepared_path,
                    fast_mode=pipeline_fast,
                    include_tracked_video=include_media,
                    budget_mode=True,
                )
                if include_media and not analysis.tracked_video_bytes:
                    logger.warning(
                        "behavior/analyze: tracked video missing — retry without budget cap",
                    )
                    analysis = run_cross_platform_video_analysis(
                        prepared_path,
                        fast_mode=True,
                        include_tracked_video=True,
                        budget_mode=False,
                    )
            scores = dict(analysis.scores) if isinstance(analysis.scores, dict) else {}

            deepface_video = {"summary": {}, "dominant": None, "frame_count": 0}
            chat_video: dict = {}
            if include_deepface and openface_results_weak(scores):
                try:
                    deepface_video = predict_video_path(
                        prepared_path,
                        max_frames=6,
                        sample_fps=2.0,
                    )
                except Exception as deepface_exc:
                    logger.warning(
                        "behavior/analyze deepface fallback failed: %s",
                        deepface_exc,
                    )

            if openface_results_weak(scores):
                scores = merge_emotion_fallback(
                    scores,
                    deepface_video=deepface_video,
                    chat_video=chat_video,
                )
                analysis = OpenFaceAnalysisResult(
                    scores=scores,
                    peak_timestamps=analysis.peak_timestamps,
                    face_visibility_ratio=float(
                        scores.get("face_visibility_ratio")
                        or analysis.face_visibility_ratio
                    ),
                    au_summary=scores.get("au_summary")
                    if isinstance(scores.get("au_summary"), list)
                    else analysis.au_summary,
                    behavioral_insights=scores.get("behavioral_insights")
                    if isinstance(scores.get("behavioral_insights"), list)
                    else analysis.behavioral_insights,
                    recommendations=scores.get("recommendations")
                    if isinstance(scores.get("recommendations"), list)
                    else analysis.recommendations,
                    tracked_video_bytes=analysis.tracked_video_bytes,
                    tracked_video_ext=analysis.tracked_video_ext,
                )
            dominant_state = str(scores.get("dominant_state") or "neutral").strip().lower()

            openface_summary = {
                "active_aus": scores.get("active_aus") or [],
                "state_probabilities": scores.get("state_probabilities") or {},
                "matched_aus_by_state": scores.get("matched_aus_by_state") or {},
                "dominant_states": scores.get("dominant_states") or [],
                "max_score": int(scores.get("max_score") or 0),
                "face_visibility_ratio": float(analysis.face_visibility_ratio),
                "au_summary": analysis.au_summary if isinstance(analysis.au_summary, list) else [],
                "recommendations": analysis.recommendations
                if isinstance(analysis.recommendations, list)
                else [],
            }

            result = MentalHealthResult.objects.create(
                user=request.user,
                stress_score=int(scores.get("stress_score") or 0),
                anxiety_score=int(scores.get("anxiety_score") or 0),
                depression_score=int(scores.get("depression_score") or 0),
                dominant_state=dominant_state,
                source_type=source_type,
                scan_type=scan_type,
                behavioral_insights=analysis.behavioral_insights,
                reaction_app_name=source_app_name,
                reaction_package_name=source_package_name,
                openface_summary=openface_summary,
            )
            if include_media and analysis.tracked_video_bytes:
                result.analyzed_video.save(
                    f"openface_{result.id}{analysis.tracked_video_ext or '.avi'}",
                    ContentFile(analysis.tracked_video_bytes),
                    save=True,
                )

            # Extract top 2–3 peak frames as expiring snapshots
            created_snapshots = []
            expires_at = default_snapshot_expiry()
            elapsed_before_snaps = time.perf_counter() - started_at
            if include_media and elapsed_before_snaps < 32.0:
                snapshot_paths = extract_snapshots(
                    input_video_path=prepared_path or tmp_path,
                    timestamps=analysis.peak_timestamps,
                    out_dir=tempfile.mkdtemp(prefix="mindsync-snapshots-"),
                    max_images=2,
                )
                for p in snapshot_paths[:3]:
                    try:
                        with open(p, "rb") as f:
                            data = f.read()
                        snap = FaceSnapshot.objects.create(
                            user=request.user,
                            detected_state=dominant_state,
                            expires_at=expires_at,
                        )
                        snap.image.save(
                            os.path.basename(p),
                            ContentFile(data),
                            save=True,
                        )
                        created_snapshots.append(
                            {
                                "id": snap.id,
                                "image_url": snap.image.url if snap.image else "",
                                "detected_state": snap.detected_state,
                                "expires_at": snap.expires_at.isoformat(),
                            }
                        )
                    except Exception:
                        continue

            return response.Response(
                {
                    "id": result.id,
                    "timestamp": result.timestamp.isoformat(),
                    "source_type": result.source_type,
                    "scan_type": result.scan_type,
                    "stress_score": result.stress_score,
                    "anxiety_score": result.anxiety_score,
                    "depression_score": result.depression_score,
                    "dominant_state": result.dominant_state,
                    "overall_severity_score": max(
                        result.stress_score,
                        result.anxiety_score,
                        result.depression_score,
                    ),
                    "score_breakdown": {
                        "stress": result.stress_score,
                        "anxiety": result.anxiety_score,
                        "depression": result.depression_score,
                        "dominant_states": scores.get("dominant_states") or [],
                        "max_score": int(scores.get("max_score") or 0),
                    },
                    "active_aus": scores.get("active_aus") or [],
                    "matched_aus_by_state": scores.get("matched_aus_by_state") or {},
                    "au_disease_table": scores.get("au_disease_table") or {},
                    "state_probabilities": scores.get("state_probabilities") or {},
                    "face_visibility_ratio": analysis.face_visibility_ratio,
                    "face_visible": analysis.face_visibility_ratio >= 0.01,
                    "behavioral_insights": analysis.behavioral_insights,
                    "au_summary": analysis.au_summary,
                    "recommendations": analysis.recommendations,
                    "analyzed_video_url": _absolute_media_url(request, result.analyzed_video),
                    "peak_snapshots": created_snapshots,
                    "fast_mode": fast_mode,
                    "pipeline_budget_40s": True,
                    "warmup_status": warmup_status,
                    "media_included": include_media,
                    "processing_time_ms": int((time.perf_counter() - started_at) * 1000),
                    "deepface_emotion_summary": deepface_video.get("summary") or {},
                    "deepface_dominant_emotion": deepface_video.get("dominant"),
                    "deepface_frames_analyzed": int(deepface_video.get("frame_count") or 0),
                    "web_style_prediction": chat_video.get("prediction"),
                    "web_style_confidence": chat_video.get("confidence"),
                    "web_style_summary": chat_video.get("summary") or {},
                    "analysis_source": scores.get("analysis_source")
                    or ("openface" if openface_host else "au_video_tracker"),
                    "pipeline": "unified_openface_v1",
                    "pipeline_preprocessing": {
                        "prefer_reencode": True,
                        "scan_type": scan_type,
                        "fast_mode": fast_mode,
                        "prepared_duration_sec": round(float(prepared_duration), 2)
                        if prepared_path
                        else 0.0,
                    },
                    "tracked_video_included": bool(analysis.tracked_video_bytes),
                    "reaction_app_name": result.reaction_app_name,
                    "reaction_package_name": result.reaction_package_name,
                    "openface_summary": result.openface_summary or {},
                },
                status=status.HTTP_200_OK,
            )
        except RuntimeError as e:
            msg = str(e)
            logger.warning("behavior/analyze rejected: %s", msg)
            return response.Response(
                {
                    "error": msg,
                    "detail": msg,
                    "hint": (
                        "Use a short MP4/MOV clip (under 30s), keep your face visible, "
                        "and wait for recording to finish before analyzing."
                    ),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            logger.exception("behavior/analyze failed")
            return response.Response(
                {"error": str(e), "detail": "Face behavior analysis failed on the server."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        finally:
            if tmp_path:
                _safe_unlink(tmp_path)
            if prepared_path and prepared_path != tmp_path:
                _safe_unlink(prepared_path)


def _absolute_media_url(request, file_field) -> str:
    if not file_field:
        return ""
    rel = file_field.url
    if rel.startswith("http://") or rel.startswith("https://"):
        return rel
    return request.build_absolute_uri(rel)


class FaceBehaviorWarmupView(views.APIView):
    """POST/GET — preload emotion + face mesh (or OpenFace on Windows) while user records."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request, *args, **kwargs):
        return self._warm()

    def post(self, request, *args, **kwargs):
        return self._warm()

    def _warm(self):
        from .analysis_warmup import ensure_behavior_models_warm

        status_payload = ensure_behavior_models_warm()
        return response.Response(
            {"ready": bool(status_payload.get("mediapipe_or_openface")),
             "models": status_payload},
            status=status.HTTP_200_OK,
        )


class FaceBehaviorLatestView(views.APIView):
    """GET latest OpenFace scan with tracked landmark video for Home / widgets."""

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        row = (
            MentalHealthResult.objects.filter(user=request.user)
            .order_by("-timestamp")
            .first()
        )
        if row is None:
            return response.Response({"has_scan": False}, status=status.HTTP_200_OK)

        return response.Response(
            {
                "has_scan": True,
                "id": row.id,
                "timestamp": row.timestamp.isoformat(),
                "dominant_state": row.dominant_state,
                "stress_score": row.stress_score,
                "anxiety_score": row.anxiety_score,
                "depression_score": row.depression_score,
                "overall_severity_score": max(
                    row.stress_score, row.anxiety_score, row.depression_score
                ),
                "analyzed_video_url": _absolute_media_url(request, row.analyzed_video),
                "behavioral_insights": row.behavioral_insights or [],
                "openface_summary": row.openface_summary or {},
            },
            status=status.HTTP_200_OK,
        )
