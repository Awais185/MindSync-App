from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone

import os

class ScreenTimeSession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='screentime_sessions')
    start_time = models.DateTimeField(auto_now_add=True)
    end_time = models.DateTimeField(null=True, blank=True)
    total_duration = models.DurationField(default=0) # Total duration in this session
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.user.username} - {self.start_time}"

class AppUsage(models.Model):
    session = models.ForeignKey(ScreenTimeSession, on_delete=models.CASCADE, related_name='app_usages')
    app_name = models.CharField(max_length=100)
    duration = models.DurationField(default=0)
    last_updated = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.app_name} - {self.duration}"

class DailyUsage(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='daily_usages')
    date = models.DateField(auto_now_add=True)
    total_screen_time = models.DurationField(default=0)
    social_media_time = models.DurationField(default=0)
    
    class Meta:
        unique_together = ('user', 'date')

    def __str__(self):
        return f"{self.user.username} - {self.date}"


class MentalHealthResult(models.Model):
    SOURCE_UNLOCK = "unlock"
    SOURCE_SCREEN_ON = "screen_on"
    SOURCE_VIDEO_WATCH = "video_watch"
    SOURCE_RANDOM_USAGE = "random_usage"

    SOURCE_CHOICES = (
        (SOURCE_UNLOCK, "Unlock"),
        (SOURCE_SCREEN_ON, "Screen On"),
        (SOURCE_VIDEO_WATCH, "Video Watch"),
        (SOURCE_RANDOM_USAGE, "Random Usage"),
    )
    SCAN_RECORDED = "recorded"
    SCAN_UPLOADED = "uploaded"
    SCAN_CHOICES = (
        (SCAN_RECORDED, "Recorded"),
        (SCAN_UPLOADED, "Uploaded"),
    )

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="mental_health_results",
    )
    timestamp = models.DateTimeField(default=timezone.now, db_index=True)
    stress_score = models.PositiveSmallIntegerField(default=0)
    anxiety_score = models.PositiveSmallIntegerField(default=0)
    depression_score = models.PositiveSmallIntegerField(default=0)
    dominant_state = models.CharField(max_length=20, default="stress", db_index=True)
    source_type = models.CharField(max_length=20, choices=SOURCE_CHOICES, db_index=True)
    scan_type = models.CharField(max_length=20, choices=SCAN_CHOICES, default=SCAN_RECORDED)
    behavioral_insights = models.JSONField(default=list, blank=True)
    analyzed_video = models.FileField(upload_to="face_analyzed_videos/", null=True, blank=True)
    # Background reaction monitor (OpenFace) — app context from Android tracker
    reaction_app_name = models.CharField(max_length=120, blank=True, default="")
    reaction_package_name = models.CharField(max_length=200, blank=True, default="")
    openface_summary = models.JSONField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["user", "timestamp"]),
            models.Index(fields=["user", "source_type", "timestamp"]),
        ]

    def __str__(self) -> str:
        return f"{self.user_id} {self.dominant_state} {self.stress_score}/{self.anxiety_score}/{self.depression_score}"


def _snapshot_upload_to(instance: "FaceSnapshot", filename: str) -> str:
    base, ext = os.path.splitext(filename)
    ext = (ext or ".jpg").lower()
    return f"face_snapshots/user_{instance.user_id}/{instance.id}{ext}"


class FaceSnapshot(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="face_snapshots",
    )
    image = models.ImageField(upload_to=_snapshot_upload_to)
    detected_state = models.CharField(max_length=20, default="stress", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    expires_at = models.DateTimeField(db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "created_at"]),
            models.Index(fields=["expires_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user_id} snapshot {self.detected_state}"


def _facial_expression_upload_to(instance: "FacialExpressionCapture", filename: str) -> str:
    base, ext = os.path.splitext(filename)
    ext = (ext or ".mp4").lower()
    if ext not in {".mp4", ".mov", ".webm", ".avi", ".mkv"}:
        ext = ".mp4"
    return f"facial_expressions/user_{instance.user_id}/capture_{instance.id or 'new'}{ext}"


class FacialExpressionCapture(models.Model):
    """
    20s front-camera face clips during social/video usage.
    Video is processed by OpenFace; AU results are stored; video file is removed after success.
    """

    STATUS_PENDING = "pending"
    STATUS_PROCESSING = "processing"
    STATUS_COMPLETED = "completed"
    STATUS_FAILED = "failed"
    STATUS_CHOICES = (
        (STATUS_PENDING, "Pending"),
        (STATUS_PROCESSING, "Processing"),
        (STATUS_COMPLETED, "Completed"),
        (STATUS_FAILED, "Failed"),
    )

    SOURCE_VIDEO_WATCH = "video_watch"
    SOURCE_SCHEDULED = "scheduled_background"
    SOURCE_SOCIAL = "social_media"
    SOURCE_MANUAL = "manual_scan"
    SOURCE_CHOICES = (
        (SOURCE_VIDEO_WATCH, "Video watch"),
        (SOURCE_SCHEDULED, "Scheduled background"),
        (SOURCE_SOCIAL, "Social media"),
        (SOURCE_MANUAL, "Manual scan"),
    )

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="facial_expression_captures",
    )
    video = models.FileField(upload_to=_facial_expression_upload_to)
    source_type = models.CharField(
        max_length=32,
        choices=SOURCE_CHOICES,
        default=SOURCE_VIDEO_WATCH,
        db_index=True,
    )
    source_app_name = models.CharField(max_length=120, blank=True, default="")
    source_package_name = models.CharField(max_length=200, blank=True, default="")
    duration_seconds = models.PositiveSmallIntegerField(default=20)

    status = models.CharField(
        max_length=16,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
        db_index=True,
    )
    processing_error = models.TextField(blank=True, default="")

    stress_score = models.PositiveSmallIntegerField(default=0)
    anxiety_score = models.PositiveSmallIntegerField(default=0)
    depression_score = models.PositiveSmallIntegerField(default=0)
    dominant_state = models.CharField(max_length=32, default="neutral", db_index=True)
    active_aus = models.JSONField(default=list, blank=True)
    au_results = models.JSONField(null=True, blank=True)
    mood = models.JSONField(null=True, blank=True, help_text="Image/video mood detector output when identity matched")

    face_match_score = models.FloatField(null=True, blank=True)
    client_timestamp_ms = models.BigIntegerField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    processed_at = models.DateTimeField(null=True, blank=True, db_index=True)
    video_deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "facial_expression_capture"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "created_at"]),
            models.Index(fields=["user", "status"]),
            models.Index(fields=["status", "created_at"]),
        ]

    def __str__(self) -> str:
        return f"FacialExpression #{self.id} user={self.user_id} {self.status}"


def _face_mood_image_upload_to(instance: "FaceMoodScan", filename: str) -> str:
    return f"face_mood_scans/user_{instance.user_id}/img_{instance.id or 'new'}_{filename}"


def _face_mood_video_upload_to(instance: "FaceMoodScan", filename: str) -> str:
    return f"face_mood_scans/user_{instance.user_id}/vid_{instance.id or 'new'}_{filename}"


class FaceMoodScan(models.Model):
    """Mood detector results after a successful face identity match."""

    MODALITY_IMAGE = "image"
    MODALITY_VIDEO = "video"
    MODALITY_CHOICES = (
        (MODALITY_IMAGE, "Image"),
        (MODALITY_VIDEO, "Video"),
    )

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="face_mood_scans",
    )
    mood = models.JSONField(default=dict, blank=True)
    modality = models.CharField(max_length=16, choices=MODALITY_CHOICES, db_index=True)
    matched = models.BooleanField(default=True)
    source = models.CharField(max_length=32, default="verify_track", db_index=True)
    capture_image = models.ImageField(
        upload_to=_face_mood_image_upload_to,
        null=True,
        blank=True,
    )
    capture_video = models.FileField(
        upload_to=_face_mood_video_upload_to,
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "face_mood_scan"
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "created_at"])]

    def __str__(self) -> str:
        return f"FaceMoodScan #{self.id} user={self.user_id} {self.modality}"


class FaceAnalysis(models.Model):
    """OpenFace AU results from 20s background face chunks (no video stored)."""

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="face_analyses",
    )
    timestamp = models.DateTimeField(default=timezone.now, db_index=True)
    source_package = models.CharField(max_length=200, blank=True, default="")
    source_type = models.CharField(max_length=32, blank=True, default="video_watch")
    match_score = models.FloatField(null=True, blank=True)
    emotion_label = models.CharField(max_length=32, blank=True, default="")
    confidence_score = models.FloatField(null=True, blank=True)
    action_units = models.JSONField(default=list, blank=True)
    head_pose = models.JSONField(default=dict, blank=True)
    gaze_data = models.JSONField(default=dict, blank=True)
    openface_payload = models.JSONField(default=dict, blank=True)
    stress_score = models.PositiveSmallIntegerField(default=0)
    anxiety_score = models.PositiveSmallIntegerField(default=0)
    depression_score = models.PositiveSmallIntegerField(default=0)
    processing_error = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "face_analysis"
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "created_at"])]

    def __str__(self) -> str:
        return f"FaceAnalysis #{self.id} user={self.user_id}"

    @property
    def needs_openface_processing(self) -> bool:
        if self.status in {self.STATUS_PENDING, self.STATUS_FAILED}:
            return bool(self.video)
        if self.status == self.STATUS_PROCESSING:
            return True
        return self.status == self.STATUS_COMPLETED and not self.au_results
