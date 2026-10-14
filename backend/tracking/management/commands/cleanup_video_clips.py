from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from tracking.models import VideoClip


class Command(BaseCommand):
    help = 'Remove video FILES older than 12h; keep clip metadata and analysis results'

    def add_arguments(self, parser):
        parser.add_argument(
            '--hours',
            type=int,
            default=12,
            help='Age threshold in hours (default: 12)',
        )

    def handle(self, *args, **options):
        hours = max(1, int(options['hours']))
        cutoff = timezone.now() - timedelta(hours=hours)
        qs = VideoClip.objects.filter(created_at__lt=cutoff).exclude(file='')
        count = qs.count()
        deleted_files = 0
        for clip in qs.iterator():
            if clip.file:
                try:
                    clip.file.delete(save=True)
                    deleted_files += 1
                except OSError:
                    pass
        self.stdout.write(
            self.style.SUCCESS(
                f'Removed {deleted_files} video file(s) from {count} clip(s); analysis rows kept.'
            )
        )
