"""Daily aggregates and temporary video uploads for web/desktop tracking."""

from django.contrib.auth.models import User
from django.db import models


class ScreenTime(models.Model):
    """
    Per-user daily screen metrics (web / desktop tracker).
    All time fields are stored in seconds (integer).
    """

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='screen_time_days')
    date = models.DateField(db_index=True)
    total_screen_time = models.PositiveIntegerField(default=0)
    social_media_time = models.PositiveIntegerField(default=0)
    video_watch_time = models.PositiveIntegerField(default=0)
    sleep_time = models.PositiveIntegerField(default=0)
    late_night_activity = models.PositiveIntegerField(default=0)
    is_finalized = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=('user', 'date'), name='uniq_screentime_user_date'),
        ]
        ordering = ['-date']

    def __str__(self) -> str:
        return f'{self.user_id} {self.date} total={self.total_screen_time}s'


class ScreenTimeSession(models.Model):
    """RN Android per-user daily total in milliseconds."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='screen_time_sessions')
    date = models.DateField(db_index=True)
    total_ms = models.PositiveBigIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'screen_time_sessions'
        constraints = [
            models.UniqueConstraint(fields=('user', 'date'), name='uniq_screen_time_session_user_date'),
        ]
        ordering = ['-date']


class ScreenTimeWeekly(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='screen_time_weekly')
    week_start = models.DateField(db_index=True)
    total_ms = models.PositiveBigIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'screen_time_weekly'
        constraints = [
            models.UniqueConstraint(fields=('user', 'week_start'), name='uniq_screen_time_weekly_user_week'),
        ]


class ScreenTimeMonthly(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='screen_time_monthly')
    year_month = models.CharField(max_length=7, db_index=True)
    total_ms = models.PositiveBigIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'screen_time_monthly'
        constraints = [
            models.UniqueConstraint(fields=('user', 'year_month'), name='uniq_screen_time_monthly_user_ym'),
        ]


class VideoClip(models.Model):
    """Screen-recording clip; video file removed after 12h, analysis results kept."""

    STATUS_PENDING = 'pending'
    STATUS_PROCESSING = 'processing'
    STATUS_COMPLETED = 'completed'
    STATUS_FAILED = 'failed'
    STATUS_CHOICES = (
        (STATUS_PENDING, 'Pending'),
        (STATUS_PROCESSING, 'Processing'),
        (STATUS_COMPLETED, 'Completed'),
        (STATUS_FAILED, 'Failed'),
    )

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='video_clips')
    file = models.FileField(upload_to='video_clips/%Y/%m/%d/')
    platform = models.CharField(max_length=64, db_index=True)
    source_package = models.CharField(max_length=200, blank=True, null=True)
    duration_seconds = models.PositiveIntegerField(default=0)
    chunk_index = models.PositiveIntegerField(
        default=0,
        help_text='0-based segment index for this screen-recording session (30s chunks).',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    # Optional client clock at upload (ISO string also accepted in API)
    client_timestamp = models.DateTimeField(null=True, blank=True)
    analysis_status = models.CharField(
        max_length=16,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
        db_index=True,
    )
    analysis_error = models.TextField(blank=True)
    script_text = models.TextField(blank=True)
    content_type = models.JSONField(default=dict, blank=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self) -> str:
        return f'{self.user_id} {self.platform} {self.created_at}'


class FaceVerificationEvent(models.Model):
    """Per-event identity verification result for unlock/screen-on/app-resume tracking gates."""

    EVENT_UNLOCK = 'unlock'
    EVENT_SCREEN_ON = 'screen_on'
    EVENT_APP_RESUME = 'app_resume'
    EVENT_CHOICES = (
        (EVENT_UNLOCK, 'Phone Unlock'),
        (EVENT_SCREEN_ON, 'Screen On'),
        (EVENT_APP_RESUME, 'App Resume'),
    )

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='face_verification_events',
    )
    event_type = models.CharField(max_length=20, choices=EVENT_CHOICES, db_index=True)
    unlock_timestamp = models.DateTimeField(null=True, blank=True)
    screen_on_timestamp = models.DateTimeField(null=True, blank=True)
    session_duration_seconds = models.PositiveIntegerField(default=0)
    verified_face_match_percent = models.FloatField(default=0.0)
    is_verified = models.BooleanField(default=False, db_index=True)
    app_usage_stats = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'created_at']),
            models.Index(fields=['user', 'event_type']),
        ]

    def __str__(self) -> str:
        return (
            f'{self.user_id} {self.event_type} verified={self.is_verified} '
            f'match={self.verified_face_match_percent:.2f}%'
        )
