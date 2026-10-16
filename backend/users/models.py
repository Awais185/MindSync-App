from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone


class UserProfile(models.Model):
    STUDENT = 'student'
    PROFESSIONAL = 'professional'
    OTHER = 'other'
    PROFESSION_CHOICES = [
        (STUDENT, 'Student'),
        (PROFESSIONAL, 'Professional'),
        (OTHER, 'Other'),
    ]

    AGE_4_15 = '4 - 15 years'
    AGE_16_30 = '16 - 30 years'
    AGE_30_PLUS = '30+ years'
    AGE_RANGE_CHOICES = [
        (AGE_4_15, '4 - 15 years'),
        (AGE_16_30, '16 - 30 years'),
        (AGE_30_PLUS, '30+ years'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    profession = models.CharField(
        max_length=20,
        choices=PROFESSION_CHOICES,
        blank=True,
        default=OTHER,
    )
    age_range = models.CharField(
        max_length=32,
        choices=AGE_RANGE_CHOICES,
        blank=True,
        default='',
        help_text='Used to gate adult ML models in background (16+ only).',
    )
    face_enrolled = models.BooleanField(default=False)
    face_image = models.ImageField(upload_to='face_enrollments/', blank=True, null=True)
    face_embedding = models.JSONField(default=list, blank=True)
    google_auth = models.BooleanField(
        default=False,
        help_text='True when the account was created or linked via Google Sign-In.',
    )

    def __str__(self):
        return f'{self.user.username} profile'


class AppUsage(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='app_usage')
    app_name = models.CharField(max_length=100)
    duration_seconds = models.IntegerField(default=0)
    date = models.DateField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'app_name', 'date')

    def __str__(self):
        return f'{self.user.username} - {self.app_name} - {self.date}'


class ScreenUsageEvent(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='screen_usage_events',
    )
    app_name = models.CharField(max_length=200)
    package_name = models.CharField(max_length=200, db_index=True)
    usage_time = models.IntegerField(help_text='Duration in seconds')
    date = models.DateField(db_index=True)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField(db_index=True)

    class Meta:
        ordering = ['-end_time']
        indexes = [
            models.Index(fields=['user', 'date']),
            models.Index(fields=['user', 'end_time']),
        ]

    def __str__(self):
        return f'{self.user.username} - {self.package_name} - {self.usage_time}s'


class VideoChunkAnalysis(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='video_chunk_analyses',
    )
    chunk_id = models.CharField(max_length=64, db_index=True)
    session_id = models.CharField(max_length=64, db_index=True)
    script_text = models.TextField(blank=True, default='')
    source_package = models.CharField(max_length=200, blank=True, null=True)
    client_created_at_ms = models.BigIntegerField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    content_type = models.JSONField(blank=True, default=dict)
    duration_seconds = models.PositiveIntegerField(default=0)
    platform = models.CharField(max_length=64, blank=True)
    source_clip = models.ForeignKey(
        'tracking.VideoClip',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='analysis_records',
    )
    behavior_analyzed_at = models.DateTimeField(blank=True, null=True)
    behavior_result = models.CharField(max_length=64, blank=True, default='')
    classification_outputs = models.JSONField(blank=True, default=dict)
    confidence_score = models.FloatField(blank=True, null=True)
    prediction_error = models.TextField(blank=True, default='')
    behavior_results = models.JSONField(blank=True, default=dict)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'created_at']),
            models.Index(fields=['platform']),
        ]

    def __str__(self):
        return f'{self.user_id} chunk {self.chunk_id}'


class ParentChildLink(models.Model):
    parent = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='parent_child_links_as_parent',
    )
    child = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='parent_child_links_as_child',
    )
    label = models.CharField(max_length=120, blank=True, help_text="e.g. Sarah's phone")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('parent', 'child')

    def __str__(self):
        return f'{self.parent_id} -> {self.child_id}'


class ChildReportedApp(models.Model):
    child_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='reported_apps',
    )
    package_name = models.CharField(max_length=200, db_index=True)
    app_label = models.CharField(max_length=300, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['app_label']
        unique_together = ('child_user', 'package_name')

    def __str__(self):
        return f'{self.child_user_id} {self.package_name}'


class BlockedAppPackage(models.Model):
    child_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='blocked_app_packages',
    )
    package_name = models.CharField(max_length=200, db_index=True)
    blocked = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['package_name']
        unique_together = ('child_user', 'package_name')

    def __str__(self):
        return f'{self.child_user_id} {self.package_name}'


class CommunityPost(models.Model):
    CATEGORY_STRESS = 'stress'
    CATEGORY_SELFCARE = 'selfcare'
    CATEGORY_WELLNESS = 'wellness'
    CATEGORY_MINDFULNESS = 'mindfulness'
    CATEGORY_OTHER = 'other'
    CATEGORY_CHOICES = [
        (CATEGORY_STRESS, 'Stress'),
        (CATEGORY_SELFCARE, 'SelfCare'),
        (CATEGORY_WELLNESS, 'Wellness'),
        (CATEGORY_MINDFULNESS, 'Mindfulness'),
        (CATEGORY_OTHER, 'Other'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='community_posts')
    content = models.TextField()
    category = models.CharField(
        max_length=30,
        choices=CATEGORY_CHOICES,
        default=CATEGORY_WELLNESS,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['category', 'created_at'])]

    def __str__(self):
        return f'Post {self.id} by {self.user_id}'


class CommunityPostComment(models.Model):
    post = models.ForeignKey(
        CommunityPost,
        on_delete=models.CASCADE,
        related_name='comments',
    )
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='community_post_comments',
    )
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f'Comment {self.id}'


class CommunityPostLike(models.Model):
    post = models.ForeignKey(CommunityPost, on_delete=models.CASCADE, related_name='likes')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='community_post_likes')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        unique_together = ('post', 'user')

    def __str__(self):
        return f'Like {self.user_id} on {self.post_id}'


class DoctorProfile(models.Model):
    account = models.OneToOneField(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='doctor_profile',
        help_text='Select doctor login account (email/user).',
    )
    full_name = models.CharField(max_length=150)
    designation = models.CharField(max_length=120)
    experience_years = models.PositiveIntegerField(default=0)
    specialist = models.CharField(max_length=120)
    contact_number = models.CharField(max_length=40)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['full_name']

    def __str__(self):
        return self.full_name


class DoctorChatMessage(models.Model):
    SENDER_USER = 'user'
    SENDER_DOCTOR = 'doctor'
    SENDER_CHOICES = [
        (SENDER_USER, 'User'),
        (SENDER_DOCTOR, 'Doctor'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='doctor_messages')
    doctor = models.ForeignKey(DoctorProfile, on_delete=models.CASCADE, related_name='messages')
    sender = models.CharField(max_length=20, choices=SENDER_CHOICES)
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']
        indexes = [models.Index(fields=['user', 'doctor', 'created_at'])]

    def __str__(self):
        return f'DoctorChat {self.id}'


class TrustedContact(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='trusted_contacts')
    name = models.CharField(max_length=150)
    relationship = models.CharField(max_length=80)
    contact_number = models.CharField(max_length=40)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


def _strip_near_white_logo_background(image_field, threshold: int = 242):
    """Make near-white pixels transparent so logos blend on purple UI."""
    if not image_field:
        return
    try:
        from io import BytesIO

        from PIL import Image
    except ImportError:
        return

    image_field.open('rb')
    try:
        raw = image_field.read()
    finally:
        image_field.close()
    if not raw:
        return

    img = Image.open(BytesIO(raw)).convert('RGBA')
    pixels = img.getdata()
    cleaned = []
    for r, g, b, a in pixels:
        if r >= threshold and g >= threshold and b >= threshold:
            cleaned.append((r, g, b, 0))
        else:
            cleaned.append((r, g, b, a))
    img.putdata(cleaned)

    out = BytesIO()
    img.save(out, format='PNG')
    out.seek(0)
    base = (image_field.name or 'logo.png').rsplit('.', 1)[0]
    image_field.save(f'{base}_transparent.png', out, save=False)


class AppBranding(models.Model):
    app_name = models.CharField(max_length=120, default='MindSync')
    logo = models.ImageField(upload_to='branding/', blank=True, null=True)
    welcome_tagline = models.CharField(
        max_length=200,
        blank=True,
        default='AI-Powered Emotional Wellness',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'App Branding'
        verbose_name_plural = 'App Branding'

    def save(self, *args, **kwargs):
        logo_changed = bool(self.logo)
        if self.pk:
            try:
                prior = AppBranding.objects.get(pk=self.pk)
                logo_changed = prior.logo != self.logo and bool(self.logo)
            except AppBranding.DoesNotExist:
                pass
        if logo_changed:
            _strip_near_white_logo_background(self.logo)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.app_name


class SubscriptionPlan(models.Model):
    slug = models.SlugField(max_length=40, unique=True)
    title = models.CharField(max_length=80)
    subtitle = models.CharField(max_length=160, blank=True)
    description = models.TextField(blank=True)
    price_monthly = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    features = models.JSONField(blank=True, default=list)
    button_label = models.CharField(max_length=80, default='Choose Plan')
    badge = models.CharField(max_length=80, blank=True)
    is_featured = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['sort_order', 'id']

    def __str__(self):
        return self.title


class UserWeeklyReport(models.Model):
    """Persisted 7-day report JSON per user (archived or current window)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='weekly_reports')
    week_start = models.DateField(db_index=True)
    week_end = models.DateField()
    payload = models.JSONField(blank=True, default=dict)
    generated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-week_start']
        unique_together = ('user', 'week_start')
        indexes = [models.Index(fields=['user', 'week_start'])]

    def __str__(self):
        return f'{self.user_id} {self.week_start}..{self.week_end}'


class UserMoodWindow(models.Model):
    """Rolling 7-day mood aggregation window start (resets after archive)."""

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='mood_window')
    window_start = models.DateField(default=timezone.localdate)

    class Meta:
        verbose_name = 'User mood window'

    def __str__(self):
        return f'{self.user_id} from {self.window_start}'


class UserNotification(models.Model):
    """In-app notification for a user (hard-deleted via API)."""

    EVENT_WELCOME = 'welcome'
    EVENT_WEEKLY_REPORT = 'weekly_report'
    EVENT_PASSWORD_RESET_REQUESTED = 'password_reset_requested'
    EVENT_PASSWORD_CHANGED = 'password_changed'
    EVENT_LOW_WELLBEING = 'low_wellbeing'

    EVENT_CHOICES = [
        (EVENT_WELCOME, 'Welcome'),
        (EVENT_WEEKLY_REPORT, 'Weekly report'),
        (EVENT_PASSWORD_RESET_REQUESTED, 'Password reset requested'),
        (EVENT_PASSWORD_CHANGED, 'Password changed'),
        (EVENT_LOW_WELLBEING, 'Low wellbeing'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    event_type = models.CharField(max_length=40, choices=EVENT_CHOICES, db_index=True)
    title = models.CharField(max_length=200)
    body = models.TextField()
    action_route = models.CharField(max_length=80, blank=True, default='')
    action_label = models.CharField(max_length=80, blank=True, default='')
    priority = models.PositiveSmallIntegerField(default=0)
    is_read = models.BooleanField(default=False, db_index=True)
    dedupe_key = models.CharField(max_length=120, blank=True, default='', db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=('user', 'dedupe_key'),
                condition=~models.Q(dedupe_key=''),
                name='uniq_user_notification_dedupe',
            ),
        ]
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['user', 'is_read']),
        ]

    def __str__(self):
        return f'{self.user_id} {self.event_type} {self.title[:40]}'
