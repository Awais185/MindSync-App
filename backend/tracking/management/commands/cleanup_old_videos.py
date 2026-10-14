"""
Delete screen-recording video FILES older than 12 hours.
Keeps VideoClip rows and VideoChunkAnalysis results (script, behavior, etc.).

Usage:
    python manage.py cleanup_old_videos
"""

from datetime import timedelta
import logging
import os

from django.core.management.base import BaseCommand
from django.utils import timezone

from face_detection.models import FacialExpressionCapture
from tracking.models import VideoClip

logger = logging.getLogger(__name__)

DEFAULT_RETENTION_HOURS = 12


class Command(BaseCommand):
    help = (
        'Delete screen-recording video files older than 12 hours; '
        'keep analysis results in the database.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--hours',
            type=int,
            default=DEFAULT_RETENTION_HOURS,
            help=f'Delete video files older than this many hours (default: {DEFAULT_RETENTION_HOURS})',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be deleted without actually deleting',
        )

    def handle(self, *args, **options):
        hours = max(1, int(options['hours']))
        dry_run = options['dry_run']
        cutoff_time = timezone.now() - timedelta(hours=hours)

        old_clips = VideoClip.objects.filter(
            created_at__lt=cutoff_time,
        ).exclude(file='')
        count = old_clips.count()

        if count == 0:
            self.stdout.write(
                self.style.SUCCESS(f'No video files older than {hours} hours to remove.')
            )
            return

        if dry_run:
            self.stdout.write(
                self.style.WARNING(
                    f'[DRY RUN] Would remove files for {count} clip(s) before {cutoff_time.isoformat()}'
                )
            )
            return

        removed = 0
        for clip in old_clips.iterator():
            try:
                if clip.file:
                    path = clip.file.path
                    clip.file.delete(save=True)
                    if path and os.path.isfile(path):
                        os.remove(path)
                    removed += 1
                    logger.info('Removed video file for clip %s (analysis kept)', clip.id)
            except Exception as e:
                logger.error('Failed to remove file for clip %s: %s', clip.id, e)

        face_removed = 0
        old_face = FacialExpressionCapture.objects.filter(
            created_at__lt=cutoff_time,
        ).exclude(video='')
        for row in old_face.iterator():
            try:
                if row.video:
                    path = row.video.path
                    row.video.delete(save=True)
                    if path and os.path.isfile(path):
                        os.remove(path)
                    face_removed += 1
                    logger.info(
                        'Removed facial expression video for capture %s (AU results kept)',
                        row.id,
                    )
            except Exception as e:
                logger.error('Failed to remove facial video for capture %s: %s', row.id, e)

        self.stdout.write(
            self.style.SUCCESS(
                f'Removed {removed} screen clip file(s) and {face_removed} facial expression '
                f'file(s) older than {hours} hours; analysis rows kept.'
            )
        )
