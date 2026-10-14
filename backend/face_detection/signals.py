"""Refresh chat mental state when face-scan rows are saved."""

from __future__ import annotations

import logging

from django.db import transaction
from django.db.utils import OperationalError
from django.dispatch import receiver
from django.db.models.signals import post_save

from face_detection.models import FaceMoodScan, FacialExpressionCapture, MentalHealthResult

logger = logging.getLogger(__name__)


def _refresh_user_snapshots(user_id: int) -> None:
    if not user_id:
        return

    def _do_refresh() -> None:
        try:
            from django.contrib.auth.models import User
            from users.services.mental_state_sync import refresh_user_tracking_snapshots

            user = User.objects.filter(id=user_id).first()
            if user:
                refresh_user_tracking_snapshots(user)
        except OperationalError as exc:
            if 'locked' in str(exc).lower() or 'busy' in str(exc).lower():
                logger.warning(
                    'SQLite busy while refreshing snapshots for user_id=%s — will retry on next scan',
                    user_id,
                )
            else:
                logger.exception('Failed to refresh face-driven snapshots for user_id=%s', user_id)
        except Exception:
            logger.exception('Failed to refresh face-driven snapshots for user_id=%s', user_id)

    transaction.on_commit(_do_refresh)


@receiver(post_save, sender=MentalHealthResult)
def refresh_after_mental_health_result(sender, instance: MentalHealthResult, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    _refresh_user_snapshots(instance.user_id)


@receiver(post_save, sender=FacialExpressionCapture)
def refresh_after_facial_expression(sender, instance: FacialExpressionCapture, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    if instance.status != FacialExpressionCapture.STATUS_COMPLETED:
        return
    _refresh_user_snapshots(instance.user_id)


@receiver(post_save, sender=FaceMoodScan)
def refresh_after_face_mood_scan(sender, instance: FaceMoodScan, **kwargs) -> None:
    if kwargs.get('raw'):
        return
    try:
        from users.services.mood_weekly_service import on_mood_scan_saved

        on_mood_scan_saved(instance.user)
    except Exception:
        logger.exception('Mood window update failed for user_id=%s', instance.user_id)
    _refresh_user_snapshots(instance.user_id)
