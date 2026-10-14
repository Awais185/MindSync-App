import os

from django.contrib import admin
from django.utils.html import escape
from django.utils.safestring import mark_safe

from .admin_video_clip import admin_reprocess_video_clips, admin_run_clip_behavior
from .models import ScreenTime, VideoClip


@admin.register(ScreenTime)
class ScreenTimeAdmin(admin.ModelAdmin):
    list_display = ('user', 'date', 'total_screen_time', 'social_media_time', 'video_watch_time', 'updated_at')
    list_filter = ('date',)
    search_fields = ('user__username', 'user__email')


@admin.register(VideoClip)
class VideoClipAdmin(admin.ModelAdmin):
    actions = (admin_reprocess_video_clips, admin_run_clip_behavior)
    ordering = ('-created_at',)
    list_display = (
        'created_at',
        'user',
        'platform',
        'chunk_index',
        'analysis_status',
        'behavior_from_analysis',
        'confidence_from_analysis',
        'duration_seconds',
    )
    list_filter = ('platform', 'analysis_status', 'created_at')
    search_fields = ('user__username', 'user__email', 'platform', 'script_text', 'analysis_error')
    raw_id_fields = ('user',)

    @admin.display(description='Behavior')
    def behavior_from_analysis(self, obj):
        row = obj.analysis_records.order_by('-created_at').first()
        if not row:
            return '—'
        if row.behavior_result:
            conf = f' ({row.confidence_score:.2f})' if row.confidence_score is not None else ''
            return f'{row.behavior_result}{conf}'
        if row.prediction_error:
            return f'error: {row.prediction_error[:80]}'
        return 'pending'

    @admin.display(description='Confidence')
    def confidence_from_analysis(self, obj):
        row = obj.analysis_records.order_by('-created_at').first()
        if row and row.confidence_score is not None:
            return f'{row.confidence_score:.3f}'
        return '—'

    @admin.display(description='Analysis row')
    def linked_analysis_id(self, obj):
        row = obj.analysis_records.order_by('-created_at').first()
        return row.id if row else '—'

    @admin.display(description='Video file')
    def file_status(self, obj):
        name = (obj.file.name or '').strip()
        if not name:
            return 'Removed after processing (script kept in analysis row)'
        path = getattr(obj.file, 'path', None)
        if path and os.path.isfile(path):
            url = escape(obj.file.url)
            return mark_safe(f'<a href="{url}" target="_blank" rel="noopener">Download</a>')
        return mark_safe(
            f'File missing on disk: <code>{escape(name)}</code> '
            '(deleted after analysis or cleanup)'
        )

    readonly_fields = (
        'created_at',
        'processed_at',
        'analysis_error',
        'behavior_from_analysis',
        'linked_analysis_id',
        'file_status',
    )
    fieldsets = (
        (
            None,
            {
                'fields': (
                    'user',
                    'file_status',
                    'platform',
                    'source_package',
                    'chunk_index',
                    'duration_seconds',
                    'client_timestamp',
                    'analysis_status',
                    'processed_at',
                    'analysis_error',
                ),
            },
        ),
        (
            'Pipeline output',
            {
                'fields': (
                    'script_text',
                    'content_type',
                    'linked_analysis_id',
                    'behavior_from_analysis',
                ),
            },
        ),
        ('Timestamps', {'fields': ('created_at',)}),
    )
