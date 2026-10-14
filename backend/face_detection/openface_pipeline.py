from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

import cv2
import pandas as pd
from django.utils import timezone
try:
    from imageio_ffmpeg import get_ffmpeg_exe
except Exception:  # pragma: no cover - optional import at runtime
    get_ffmpeg_exe = None

from .openface_results import analyze_openface_csv


OPENFACE_ROOT = os.path.join(
    os.path.dirname(__file__),
    "face_video_model",
    "OpenFace_2.2.0_win_x64",
    "OpenFace_2.2.0_win_x64",
)


def _feature_extraction_exe() -> str:
    exe = os.environ.get("OPENFACE_FEATURE_EXTRACTION_EXE", "").strip()
    if exe:
        return exe
    return os.path.join(OPENFACE_ROOT, "FeatureExtraction.exe")


def _ensure_openface_available() -> None:
    exe = _feature_extraction_exe()
    if not os.path.exists(exe):
        raise RuntimeError(f"OpenFace executable not found at: {exe}")


def _safe_unlink(path: str) -> None:
    try:
        if path and os.path.exists(path):
            os.unlink(path)
    except OSError:
        pass


def _rm_tree(path: str) -> None:
    try:
        if path and os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
    except OSError:
        pass


def _ffmpeg_error_detail(proc: subprocess.CompletedProcess[str]) -> str:
    """Return the actionable tail of ffmpeg output (skip version/config banner)."""
    text = "\n".join(
        part.strip()
        for part in (proc.stderr or "", proc.stdout or "")
        if part and part.strip()
    )
    if not text:
        return "FFmpeg failed with no output."

    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    noise_prefixes = (
        "ffmpeg version",
        "built with gcc",
        "built with",
        "configuration:",
        "copyright",
        "  lib",
        "  configuration",
    )
    useful: list[str] = []
    for ln in lines:
        low = ln.lower()
        if any(low.startswith(p) for p in noise_prefixes):
            continue
        if ln.startswith("--enable-"):
            continue
        useful.append(ln)

    if useful:
        return " | ".join(useful[-6:])[:450]
    return lines[-1][:450] if lines else "FFmpeg failed with no output."


def _ffmpeg_exe() -> str:
    env_ffmpeg = (os.environ.get("FFMPEG_EXE") or "").strip()
    if env_ffmpeg and os.path.exists(env_ffmpeg):
        return env_ffmpeg
    if get_ffmpeg_exe is not None:
        try:
            exe = get_ffmpeg_exe()
            if exe and os.path.exists(exe):
                return exe
        except Exception:
            pass
    raise RuntimeError(
        "FFmpeg is required for H.264/AAC conversion but is not available. "
        "Install imageio-ffmpeg or set FFMPEG_EXE."
    )


def _validate_video_integrity(video_path: str) -> tuple[bool, str]:
    # Short trimmed clips (fast_mode) can be a few KB after ffmpeg/OpenCV prep.
    if not os.path.exists(video_path) or os.path.getsize(video_path) < 1024:
        return False, "Video file is empty or too small."
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return False, "Video container/codec not readable."
    try:
        frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0)
        ok, _ = cap.read()
        if not ok:
            return False, "Video has no decodable frames."
        # Phone / browser uploads often lack moov metadata until ffmpeg remuxes.
        if frames > 0 and fps > 0:
            return True, ""
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        readable = 0
        for _ in range(8):
            ok2, _ = cap.read()
            if ok2:
                readable += 1
        if readable >= 2:
            return True, ""
        return False, "Video metadata is invalid or file is incomplete (moov atom missing)."
    finally:
        cap.release()


def _transcode_to_h264_aac_mp4(input_path: str, output_path: str, *, fast_mode: bool = False) -> None:
    ffmpeg = _ffmpeg_exe()
    cmd = [
        ffmpeg,
        "-y",
        "-i",
        input_path,
        "-map",
        "0:v:0",
        "-map",
        "0:a:0?",
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast" if fast_mode else "veryfast",
        "-crf",
        "28" if fast_mode else "22",
        "-pix_fmt",
        "yuv420p",
        "-r",
        "20" if fast_mode else "24",
        "-vf",
        "scale=960:-2:force_original_aspect_ratio=decrease" if fast_mode else "scale=1280:-2:force_original_aspect_ratio=decrease",
        "-movflags",
        "+faststart",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-ar",
        "48000",
        output_path,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if proc.returncode != 0 or (not os.path.exists(output_path)):
        raise RuntimeError(f"FFmpeg conversion failed: {_ffmpeg_error_detail(proc)}")

    ok, reason = _validate_video_integrity(output_path)
    if not ok:
        raise RuntimeError(f"Converted video integrity check failed: {reason}")


def _convert_tracked_avi_to_browser_video(
    avi_path: str,
    *,
    expected_duration_sec: float | None = None,
) -> tuple[bytes | None, str]:
    """
    Convert OpenFace tracked AVI to browser-compatible MP4 (H.264 + AAC).
    """
    if not os.path.exists(avi_path):
        return None, ".mp4"
    tmp_out = os.path.join(
        tempfile.gettempdir(),
        f"mindsync_tracked_{uuid.uuid4().hex[:10]}.mp4",
    )
    try:
        ffmpeg = _ffmpeg_exe()
        tracked_duration = _video_duration_seconds(avi_path)
        speed_factor = 1.0
        if (
            expected_duration_sec is not None
            and expected_duration_sec > 0
            and tracked_duration > 0
        ):
            speed_factor = max(0.4, min(2.5, expected_duration_sec / tracked_duration))

        cmd = [
            ffmpeg,
            "-y",
            "-i",
            avi_path,
            "-map",
            "0:v:0",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "23",
            "-vf",
            f"setpts={speed_factor:.6f}*PTS",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            tmp_out,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
        if proc.returncode != 0 or (not os.path.exists(tmp_out)):
            raise RuntimeError(
                f"Tracked video conversion failed: {_ffmpeg_error_detail(proc)}"
            )
        ok, reason = _validate_video_integrity(tmp_out)
        if not ok:
            raise RuntimeError(f"Tracked video integrity check failed: {reason}")
        if os.path.exists(tmp_out) and os.path.getsize(tmp_out) > 4096:
            with open(tmp_out, "rb") as f:
                return f.read(), ".mp4"
    except Exception:
        return None, ".mp4"
    finally:
        _safe_unlink(tmp_out)
    return None, ".mp4"


def _count_readable_frames(video_path: str, *, max_probe: int = 400) -> int:
    """How many frames OpenCV can actually decode (metadata often lies on phone MP4)."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return 0
    n = 0
    try:
        while n < max_probe:
            ok, frame = cap.read()
            if not ok or frame is None:
                break
            n += 1
    finally:
        cap.release()
    return n


def _video_duration_seconds(video_path: str) -> float:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return 0.0
    try:
        frames = float(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0.0)
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        if frames > 0 and fps > 0:
            return frames / fps
        # Phone clips: estimate from decoded frames.
        n = _count_readable_frames(video_path, max_probe=400)
        if n > 0 and fps > 0:
            return n / fps
        if n > 0:
            return n / 15.0
        return 0.0
    finally:
        cap.release()


def _openface_max_duration_seconds(*, fast_mode: bool) -> float:
    default = "35" if fast_mode else "120"
    raw = os.environ.get("OPENFACE_MAX_VIDEO_SECONDS", default).strip()
    try:
        return max(5.0, float(raw))
    except ValueError:
        return max(5.0, float(default))


def _openface_timeout_seconds(video_duration_sec: float, *, fast_mode: bool) -> int:
    env = os.environ.get("OPENFACE_TIMEOUT_SECONDS", "").strip()
    if env:
        return max(60, int(env))
    per_sec = 6 if fast_mode else 12
    base = 90 if fast_mode else 180
    estimated = int(max(1.0, video_duration_sec) * per_sec) + base
    return max(120, min(900, estimated))


def _prepare_video_opencv(
    input_path: str,
    output_path: str,
    *,
    trim_sec: float,
    target_fps: float = 12.0,
    max_width: int = 640,
) -> float:
    """
    Fallback when ffmpeg cannot read the container (e.g. moov-at-end phone/web capture).
    Writes MPEG-4 Part 2 (mp4v) which OpenFace accepts on Windows.
    """
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        raise RuntimeError("Video could not be opened for frame extraction.")

    src_fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if src_fps <= 1.0:
        src_fps = 15.0
    frame_interval = max(1, int(round(src_fps / target_fps)))
    max_frames = max(3, int(trim_sec * target_fps))

    writer: cv2.VideoWriter | None = None
    written = 0
    frame_idx = 0
    try:
        while written < max_frames:
            ok, frame = cap.read()
            if not ok or frame is None:
                break
            if frame_idx % frame_interval != 0:
                frame_idx += 1
                continue
            h, w = frame.shape[:2]
            if w > max_width:
                nh = max(1, int(h * max_width / w))
                frame = cv2.resize(frame, (max_width, nh), interpolation=cv2.INTER_AREA)
            if writer is None:
                h, w = frame.shape[:2]
                fourcc = cv2.VideoWriter_fourcc(*"mp4v")
                writer = cv2.VideoWriter(output_path, fourcc, target_fps, (w, h))
                if not writer.isOpened():
                    raise RuntimeError("Could not create OpenCV output video writer.")
            writer.write(frame)
            written += 1
            frame_idx += 1
    finally:
        cap.release()
        if writer is not None:
            writer.release()

    if written < 2:
        raise RuntimeError("Video has too few decodable frames for OpenFace.")

    out_dur = _video_duration_seconds(output_path)
    return out_dur if out_dur > 0 else written / target_fps


def _prepare_video_ffmpeg(
    input_path: str,
    output_path: str,
    *,
    trim_sec: float,
    fast_mode: bool,
) -> float:
    """FFmpeg trim/transcode with codec fallbacks (essentials builds vary)."""
    ffmpeg = _ffmpeg_exe()
    scale_vf = (
        "scale=640:-2:force_original_aspect_ratio=decrease"
        if fast_mode
        else "scale=960:-2:force_original_aspect_ratio=decrease"
    )
    last_detail = "unknown ffmpeg failure"
    for vcodec in ("libx264", "mpeg4"):
        cmd = [
            ffmpeg,
            "-y",
            "-fflags",
            "+genpts",
            "-i",
            input_path,
            "-t",
            f"{max(1.0, trim_sec):.3f}",
            "-an",
            "-c:v",
            vcodec,
        ]
        if vcodec == "libx264":
            cmd.extend(
                [
                    "-preset",
                    "ultrafast" if fast_mode else "veryfast",
                    "-crf",
                    "28" if fast_mode else "22",
                ]
            )
        cmd.extend(
            [
                "-pix_fmt",
                "yuv420p",
                "-r",
                "12" if fast_mode else "20",
                "-vf",
                scale_vf,
                "-movflags",
                "+faststart",
                output_path,
            ]
        )
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
        if proc.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 1024:
            ok, _ = _validate_video_integrity(output_path)
            if ok:
                out_dur = _video_duration_seconds(output_path)
                return out_dur if out_dur > 0 else trim_sec
        last_detail = _ffmpeg_error_detail(proc)
        _safe_unlink(output_path)
    raise RuntimeError(f"FFmpeg prep failed: {last_detail}")


def _normalize_video_for_openface(
    input_path: str,
    output_path: str,
    *,
    fast_mode: bool,
    max_video_seconds: float | None = None,
    prefer_reencode: bool = False,
) -> float:
    """
    Prepare clip for OpenFace on Windows / phone uploads.

    When prefer_reencode (phone camera clips), always transcode so rotation/codec match web.
    Otherwise: copy decodable MP4 when possible, then OpenCV, then FFmpeg.
    """
    limit = max_video_seconds if max_video_seconds and max_video_seconds > 0 else None
    if limit is None:
        limit = _openface_max_duration_seconds(fast_mode=fast_mode)

    decoded = _count_readable_frames(input_path)
    if decoded < 2:
        raise RuntimeError(
            "Uploaded video has no readable frames. "
            "Record again, wait for preview playback, then tap Use this video."
        )

    cap_dur = _video_duration_seconds(input_path)
    trim_sec = min(limit, cap_dur) if cap_dur > 0 else limit
    trim_sec = max(2.0, float(trim_sec))

    lower = str(input_path).lower()
    size = os.path.getsize(input_path)
    if (
        not prefer_reencode
        and decoded >= 6
        and size >= 12_000
        and lower.endswith((".mp4", ".mov", ".webm"))
    ):
        try:
            shutil.copy2(input_path, output_path)
            ok, _ = _validate_video_integrity(output_path)
            if ok:
                dur = _video_duration_seconds(output_path)
                return dur if dur > 0 else min(trim_sec, decoded / 12.0)
        except OSError:
            _safe_unlink(output_path)

    if prefer_reencode:
        try:
            return _prepare_video_ffmpeg(
                input_path,
                output_path,
                trim_sec=trim_sec,
                fast_mode=fast_mode,
            )
        except Exception as ff_first:
            try:
                return _prepare_video_opencv(
                    input_path,
                    output_path,
                    trim_sec=trim_sec,
                    target_fps=12.0 if fast_mode else 20.0,
                    max_width=640 if fast_mode else 960,
                )
            except Exception as opencv_exc:
                raise RuntimeError(
                    f"Could not prepare phone video for OpenFace. FFmpeg: {ff_first}. OpenCV: {opencv_exc}"
                ) from opencv_exc

    try:
        return _prepare_video_opencv(
            input_path,
            output_path,
            trim_sec=trim_sec,
            target_fps=12.0 if fast_mode else 20.0,
            max_width=640 if fast_mode else 960,
        )
    except Exception as opencv_exc:
        try:
            return _prepare_video_ffmpeg(
                input_path,
                output_path,
                trim_sec=trim_sec,
                fast_mode=fast_mode,
            )
        except Exception as ff_exc:
            raise RuntimeError(
                f"Could not prepare video for OpenFace. OpenCV: {opencv_exc}. FFmpeg: {ff_exc}"
            ) from ff_exc


def prepare_unified_analysis_video(
    input_video_path: str,
    *,
    fast_mode: bool,
) -> tuple[str, float]:
    """
    Single preprocessing entry for Deep Face Analysis (record + upload).

    Always re-encodes via FFmpeg-first normalization so OpenFace receives the same
    frame rate, resolution, and codec as camera-recorded clips.
    Returns (normalized_mp4_path, duration_sec). Caller must delete the path when done.
    """
    import logging

    log = logging.getLogger(__name__)
    decoded_in = _count_readable_frames(input_video_path)
    in_size = os.path.getsize(input_video_path) if os.path.exists(input_video_path) else 0
    out_path = os.path.join(
        tempfile.gettempdir(),
        f"mindsync_analysis_{uuid.uuid4().hex[:10]}.mp4",
    )
    duration = _normalize_video_for_openface(
        input_video_path,
        out_path,
        fast_mode=fast_mode,
        prefer_reencode=True,
    )
    decoded_out = _count_readable_frames(out_path)
    log.info(
        "DeepFace unified prep: in_frames=%s in_bytes=%s out_frames=%s out=%s duration=%.2fs fast_mode=%s",
        decoded_in,
        in_size,
        decoded_out,
        out_path,
        duration,
        fast_mode,
    )
    return out_path, duration


def _prepare_video_for_openface(
    input_path: str,
    output_path: str,
    *,
    fast_mode: bool,
    max_video_seconds: float | None = None,
    prefer_reencode: bool = False,
) -> float:
    return _normalize_video_for_openface(
        input_path,
        output_path,
        fast_mode=fast_mode,
        max_video_seconds=max_video_seconds,
        prefer_reencode=prefer_reencode,
    )


def _dominant_related_aus(state: str) -> list[str]:
    if state == "stress":
        return [
            "AU04_r", "AU07_r", "AU24_r", "AU23_r",
            "AU01_r", "AU02_r"
        ]

    if state == "anxiety":
        return [
            "AU01_r", "AU02_r", "AU05_r", "AU20_r",
            "AU25_r", "AU26_r", "AU45_r"
        ]

    if state == "depression":
        return [
            "AU15_r", "AU17_r", "AU04_r",
            "AU06_r", "AU12_r"
        ]

    if state == "neutral":
        return ["AU06_r", "AU12_r"]

    return ["AU06_r", "AU12_r", "AU15_r"]


@dataclass(frozen=True)
class OpenFaceAnalysisResult:
    scores: dict[str, Any]
    peak_timestamps: list[float]
    face_visibility_ratio: float
    au_summary: list[dict[str, Any]]
    behavioral_insights: list[str]
    recommendations: list[str]
    tracked_video_bytes: bytes | None
    tracked_video_ext: str


def run_openface_and_analyze(
    *,
    input_video_path: str,
    max_peak_frames: int = 3,
    include_tracked_video: bool = False,
    fast_mode: bool = True,
    max_video_seconds: float | None = None,
    prefer_reencode: bool = False,
    prepared_video_path: str | None = None,
) -> OpenFaceAnalysisResult:
    """
    1) Runs OpenFace FeatureExtraction.exe on a video
    2) Produces CSV in a temp directory
    3) Runs results.py logic for final scores
    4) Finds peak timestamps based on AU intensity for dominant_state
    5) Deletes all temp OpenFace outputs before returning
    """

    _ensure_openface_available()

    if _count_readable_frames(input_video_path) < 2:
        ok_src, src_reason = _validate_video_integrity(input_video_path)
        raise RuntimeError(
            f"Uploaded video is not readable: {src_reason} "
            "Re-record the clip and wait until saving finishes before uploading."
        )

    tmp_dir = tempfile.mkdtemp(prefix="mindsync-openface-")
    csv_path = ""
    use_prepared = (
        prepared_video_path
        and os.path.exists(prepared_video_path)
        and _count_readable_frames(prepared_video_path) >= 2
    )
    if use_prepared:
        normalized_input_path = prepared_video_path
        clip_duration = _video_duration_seconds(prepared_video_path)
    else:
        normalized_input_path = os.path.join(tmp_dir, f"in_{uuid.uuid4().hex[:10]}.mp4")
    try:
        if not use_prepared:
            clip_duration = _normalize_video_for_openface(
                input_video_path,
                normalized_input_path,
                fast_mode=fast_mode,
                max_video_seconds=max_video_seconds,
                prefer_reencode=prefer_reencode,
            )

        timeout_sec = _openface_timeout_seconds(clip_duration, fast_mode=fast_mode)
        out_prefix = f"openface-{uuid.uuid4().hex[:10]}"
        exe = _feature_extraction_exe()

        # Request OpenFace tracked visualization video (`-tracked`) so we can show landmark/AU UI output.
        # Keep arguments leaner for better performance.
        cmd = [
            exe,
            "-f",
            normalized_input_path,
            "-out_dir",
            tmp_dir,
            "-of",
            out_prefix,
            "-aus",
        ]
        if not fast_mode:
            cmd.extend(["-gaze", "-pose"])
        if include_tracked_video:
            cmd.append("-tracked")
        try:
            proc = subprocess.run(
                cmd,
                cwd=OPENFACE_ROOT,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                f"OpenFace timed out after {timeout_sec}s "
                f"(prepared clip ~{clip_duration:.1f}s). "
                "Try a shorter clip or set OPENFACE_TIMEOUT_SECONDS."
            ) from exc
        if proc.returncode != 0:
            raise RuntimeError(
                "OpenFace failed: "
                + (proc.stderr.strip() or proc.stdout.strip() or "unknown error")
            )

        candidate = os.path.join(tmp_dir, f"{out_prefix}.csv")
        if os.path.exists(candidate):
            csv_path = candidate
        else:
            # Fallback: pick the first CSV in tmp_dir
            csvs = [p for p in os.listdir(tmp_dir) if p.lower().endswith(".csv")]
            if not csvs:
                raise RuntimeError("OpenFace did not produce any CSV output.")
            csv_path = os.path.join(tmp_dir, csvs[0])

        scores = analyze_openface_csv(csv_path)
        dominant_state = str(scores.get("dominant_state") or "neutral").strip().lower()

        # Peak timestamps: choose frames where related AUs are highest.
        df = pd.read_csv(csv_path, on_bad_lines="skip")
        if "timestamp" not in df.columns:
            peak_ts: list[float] = []
        else:
            au_cols = _dominant_related_aus(dominant_state)
            existing = [c for c in au_cols if c in df.columns]
            if not existing:
                peak_ts = []
            else:
                per_row = df[existing].fillna(0).sum(axis=1)
                ranked = per_row.sort_values(ascending=False).head(max(1, max_peak_frames))
                peak_ts = [
                    float(df.loc[int(idx), "timestamp"])
                    for idx in ranked.index.tolist()
                    if int(idx) in df.index
                ]

        face_visibility_ratio = float(scores.get("face_visibility_ratio") or 0.0)
        au_summary = scores.get("au_summary") if isinstance(scores.get("au_summary"), list) else []
        behavioral_insights = (
            scores.get("behavioral_insights")
            if isinstance(scores.get("behavioral_insights"), list)
            else []
        )
        recommendations = (
            scores.get("recommendations") if isinstance(scores.get("recommendations"), list) else []
        )

        tracked_video_bytes: bytes | None = None
        tracked_video_ext = ".mp4"
        if include_tracked_video:
            avi_candidates = [
                os.path.join(tmp_dir, name)
                for name in os.listdir(tmp_dir)
                if name.lower().endswith(".avi")
            ]
            preferred = [
                p for p in avi_candidates if "tracked" in os.path.basename(p).lower()
            ]
            ranked = preferred or avi_candidates
            if ranked:
                expected_duration = _video_duration_seconds(normalized_input_path)
                ranked = sorted(
                    ranked,
                    key=lambda p: _video_duration_seconds(p),
                    reverse=True,
                )
                tracked_video_bytes, tracked_video_ext = _convert_tracked_avi_to_browser_video(
                    ranked[0],
                    expected_duration_sec=expected_duration,
                )
            import logging

            log = logging.getLogger(__name__)
            if tracked_video_bytes:
                log.info(
                    "OpenFace tracked video converted bytes=%s ext=%s source=%s",
                    len(tracked_video_bytes),
                    tracked_video_ext,
                    os.path.basename(ranked[0]),
                )
            else:
                log.warning(
                    "OpenFace tracked AVI conversion failed candidates=%s",
                    [os.path.basename(p) for p in ranked],
                )

        # Keep unique, sorted for nicer extraction behavior
        peak_ts = sorted({round(ts, 3) for ts in peak_ts})[:max_peak_frames]
        return OpenFaceAnalysisResult(
            scores=scores,
            peak_timestamps=peak_ts,
            face_visibility_ratio=round(face_visibility_ratio, 3),
            au_summary=au_summary,
            behavioral_insights=behavioral_insights,
            recommendations=recommendations,
            tracked_video_bytes=tracked_video_bytes,
            tracked_video_ext=tracked_video_ext,
        )
    finally:
        # Delete CSV + any temporary OpenFace artifacts immediately
        _rm_tree(tmp_dir)


def extract_snapshots(
    *,
    input_video_path: str,
    timestamps: list[float],
    out_dir: str,
    max_images: int = 3,
) -> list[str]:
    """
    Extracts up to N frames from video at given timestamps (seconds) and writes JPEGs.
    Returns list of saved file paths.
    """
    if not timestamps:
        return []

    os.makedirs(out_dir, exist_ok=True)
    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        return []

    saved: list[str] = []
    try:
        for ts in timestamps[:max_images]:
            cap.set(cv2.CAP_PROP_POS_MSEC, float(ts) * 1000.0)
            ok, frame = cap.read()
            if not ok or frame is None:
                continue
            name = f"peak_{uuid.uuid4().hex[:10]}.jpg"
            path = os.path.join(out_dir, name)
            ok2 = cv2.imwrite(path, frame)
            if ok2:
                saved.append(path)
    finally:
        cap.release()

    return saved


def default_snapshot_expiry() -> timezone.datetime:
    days = int(os.environ.get("FACE_SNAPSHOT_EXPIRE_DAYS", "10"))
    return timezone.now() + timedelta(days=max(1, days))

