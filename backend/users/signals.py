"""Auto-run behavior model when a chunk analysis row gets script text."""

from __future__ import annotations

import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import AppUsage, ScreenUsageEvent, VideoChunkAnalysis

logger = logging.getLogger(__name__)


def _needs_behavior_analysis(row: VideoChunkAnalysis) -> bool:
    if not (row.script_text or '').strip():
        return False
    if not row.behavior_analyzed_at:
        return True
    if not (row.behavior_result or '').strip():
        return True
    if row.behavior_result == 'unavailable' and not (row.prediction_error or '').strip():
        return True
    return False


def _refresh_user_snapshots(user_id: int) -> None:
    if not user_id:
        return
    try:
        from django.contrib.auth.models import User
        from users.services.mental_state_sync import refresh_user_tracking_snapshots

        user = User.objects.filter(id=user_id).first()
        if user:
            refresh_user_tracking_snapshots(user)
    except Exception:
        logger.exception('Failed to refresh tracking snapshots for user_id=%s', user_id)


@receiver(post_save, sender=VideoChunkAnalysis)
def run_behavior_model_on_chunk_save(sender, instance: VideoChunkAnalysis, created: bool, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    if getattr(instance, '_skip_behavior_signal', False):
        return

    if _needs_behavior_analysis(instance):
        from tracking.services.behavior_analysis import analyze_and_update_video_chunk

        logger.info('Running behavior model for VideoChunkAnalysis id=%s', instance.id)
        analyze_and_update_video_chunk(instance.id)
    else:
        _refresh_user_snapshots(instance.user_id)


@receiver(post_save, sender=ScreenUsageEvent)
def refresh_after_screen_usage_event(sender, instance: ScreenUsageEvent, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    _refresh_user_snapshots(instance.user_id)


@receiver(post_save, sender=AppUsage)
def refresh_after_app_usage(sender, instance: AppUsage, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    _refresh_user_snapshots(instance.user_id)
