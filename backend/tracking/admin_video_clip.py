from __future__ import annotations

from django.contrib import admin

from tracking.services.behavior_analysis import analyze_and_update_video_chunk
from tracking.services.video_analysis import backfill_incomplete_clip_results
from users.models import VideoChunkAnalysis

from .models import VideoClip


@admin.action(description='Re-run full pipeline (script + behavior) for selected clips')
def admin_reprocess_video_clips(modeladmin, request, queryset):
    ok = 0
    for clip in queryset:
        try:
            backfill_incomplete_clip_results(clip.id)
            ok += 1
        except Exception:
            pass
    modeladmin.message_user(request, f'Reprocessed {ok} clip(s).')


@admin.action(description='Run behavior model on linked analysis (script required)')
def admin_run_clip_behavior(modeladmin, request, queryset):
    done = 0
    for clip in queryset:
        row = VideoChunkAnalysis.objects.filter(source_clip=clip).order_by('-created_at').first()
        if row and (row.script_text or '').strip():
            if analyze_and_update_video_chunk(row.id):
                done += 1
    modeladmin.message_user(request, f'Behavior model updated for {done} clip(s).')
