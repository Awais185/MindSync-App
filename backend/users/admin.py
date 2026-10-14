from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import User

from .admin_video_chunk import (
    VideoChunkUserBrowserMixin,
    admin_run_behavior_model,
    format_behavior_details,
    format_script_preview,
)
from .models import (
    UserProfile,
    ScreenUsageEvent,
    UserWeeklyReport,
    UserMoodWindow,
    VideoChunkAnalysis,
    CommunityPost,
    DoctorProfile,
    DoctorChatMessage,
    TrustedContact,
    AppBranding,
    SubscriptionPlan,
)

class UserProfileInline(admin.StackedInline):
    model = UserProfile
    can_delete = False
    verbose_name_plural = 'UserProfile'

class UserAdmin(BaseUserAdmin):
    inlines = (UserProfileInline,)
    list_display = ('username', 'email', 'first_name', 'last_name', 'get_profession', 'get_face_enrolled', 'is_staff')
    
    def get_profession(self, instance):
        return instance.profile.profession
    get_profession.short_description = 'Profession'

    def get_face_enrolled(self, instance):
        return instance.profile.face_enrolled
    get_face_enrolled.short_description = 'Face Enrolled'
    get_face_enrolled.boolean = True

# Re-register UserAdmin
admin.site.unregister(User)
admin.site.register(User, UserAdmin)

@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'profession', 'face_enrolled', 'face_image')
    search_fields = ('user__username', 'user__email', 'profession')
    list_filter = ('profession', 'face_enrolled')


@admin.register(ScreenUsageEvent)
class ScreenUsageEventAdmin(admin.ModelAdmin):
    list_display = ('user', 'app_name', 'package_name', 'usage_time', 'date', 'end_time')
    list_filter = ('date',)
    search_fields = ('package_name', 'app_name', 'user__username')
    date_hierarchy = 'date'


@admin.register(UserMoodWindow)
class UserMoodWindowAdmin(admin.ModelAdmin):
    list_display = ('user', 'window_start')
    search_fields = ('user__username', 'user__email')


@admin.register(UserWeeklyReport)
class UserWeeklyReportAdmin(admin.ModelAdmin):
    list_display = ('user', 'week_start', 'week_end', 'generated_at')
    list_filter = ('week_start',)
    search_fields = ('user__username', 'user__email')
    readonly_fields = ('generated_at',)


@admin.register(VideoChunkAnalysis)
class VideoChunkAnalysisAdmin(VideoChunkUserBrowserMixin, admin.ModelAdmin):
    actions = (admin_run_behavior_model,)
    ordering = ('-created_at',)
    list_display = (
        'created_at',
        'username_display',
        'platform',
        'chunk_id',
        'behavior_result',
        'confidence_score',
        'script_preview',
        'duration_seconds',
        'source_package',
        'analysis_status_display',
    )
    search_fields = (
        'chunk_id',
        'session_id',
        'script_text',
        'behavior_result',
        'prediction_error',
        'user__username',
        'user__email',
    )
    list_filter = ('user', 'platform', 'behavior_result', 'created_at')
    readonly_fields = (
        'behavior_analyzed_at',
        'created_at',
        'script_preview_long',
        'behavior_details_panel',
    )
    date_hierarchy = 'created_at'
    raw_id_fields = ('user', 'source_clip')
    list_select_related = ('user', 'source_clip')
    list_per_page = 50
    fieldsets = (
        (
            None,
            {
                'fields': (
                    'user',
                    'source_clip',
                    'chunk_id',
                    'session_id',
                    'platform',
                    'source_package',
                    'duration_seconds',
                    'client_created_at_ms',
                ),
            },
        ),
        (
            'Vision script',
            {
                'fields': ('script_text', 'script_preview_long', 'content_type'),
            },
        ),
        (
            'Behavior model (ensemble_final_model)',
            {
                'fields': (
                    'behavior_result',
                    'confidence_score',
                    'behavior_results',
                    'classification_outputs',
                    'behavior_details_panel',
                    'prediction_error',
                    'behavior_analyzed_at',
                ),
            },
        ),
        ('Timestamps', {'fields': ('created_at',)}),
    )

    @admin.display(description='User')
    def username_display(self, obj):
        if obj.user_id:
            return obj.user.username
        return '—'

    @admin.display(description='Status')
    def analysis_status_display(self, obj):
        if (obj.prediction_error or '').strip():
            return f'error: {obj.prediction_error[:60]}'
        if (obj.script_text or '').strip() and obj.behavior_result:
            return 'complete'
        if (obj.script_text or '').strip():
            return 'script only'
        return 'pending upload/analysis'

    @admin.display(description='Script (preview)')
    def script_preview(self, obj):
        return format_script_preview(obj)

    @admin.display(description='Script preview')
    def script_preview_long(self, obj):
        return format_script_preview(obj, max_len=1200)

    @admin.display(description='Behavior details')
    def behavior_details_panel(self, obj):
        return format_behavior_details(obj)

    @admin.display(boolean=True, description='Error?')
    def has_prediction_error(self, obj):
        return bool((obj.prediction_error or '').strip())


@admin.register(CommunityPost)
class CommunityPostAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'category', 'created_at')
    list_filter = ('category', 'created_at')
    search_fields = ('user__username', 'user__email', 'content')


@admin.register(DoctorProfile)
class DoctorProfileAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'account',
        'account_email',
        'full_name',
        'designation',
        'experience_years',
        'specialist',
        'contact_number',
        'is_active',
    )
    list_filter = ('is_active', 'specialist')
    search_fields = (
        'full_name',
        'designation',
        'specialist',
        'contact_number',
        'account__email',
        'account__username',
    )
    autocomplete_fields = ('account',)

    def account_email(self, obj):
        return obj.account.email if obj.account else ''

    account_email.short_description = 'Account Email'


@admin.register(DoctorChatMessage)
class DoctorChatMessageAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'doctor', 'sender', 'created_at')
    list_filter = ('sender', 'created_at', 'doctor')
    search_fields = ('user__username', 'doctor__full_name', 'message')


@admin.register(TrustedContact)
class TrustedContactAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'name', 'relationship', 'contact_number')
    list_filter = ('relationship',)
    search_fields = ('user__username', 'name', 'contact_number')


@admin.register(AppBranding)
class AppBrandingAdmin(admin.ModelAdmin):
    list_display = ('app_name', 'logo', 'updated_at')

    def has_add_permission(self, request):
        if AppBranding.objects.exists():
            return False
        return super().has_add_permission(request)


@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'slug',
        'price_monthly',
        'is_featured',
        'is_active',
        'sort_order',
        'updated_at',
    )
    list_filter = ('is_active', 'is_featured')
    search_fields = ('title', 'slug', 'subtitle', 'badge')
    ordering = ('sort_order', 'id')
