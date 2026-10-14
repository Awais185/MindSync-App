from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.models import Q
from django.utils import timezone

from tracking.models import VideoClip
from tracking.services.video_analysis import process_video_clip_now


class Command(BaseCommand):
    help = (
        'Recover video clips missing script_text by re-running the pipeline '
        '(script generation -> behavior analysis -> DB update -> video delete).'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--hours',
            type=int,
            default=12,
            help='Inspect clips created in the last N hours (default: 12).',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=200,
            help='Maximum clips to process in one run (default: 200).',
        )
        parser.add_argument(
            '--workers',
            type=int,
            default=4,
            help='Parallel workers for processing clips (default: 4).',
        )

    def handle(self, *args, **options):
        hours = max(1, int(options['hours']))
        limit = max(1, int(options['limit']))
        workers = max(1, int(options['workers']))

        cutoff = timezone.now() - timedelta(hours=hours)
        qs = (
            VideoClip.objects.filter(created_at__gte=cutoff)
            .filter(Q(script_text__isnull=True) | Q(script_text=''))
            .distinct()
        )
        qs = qs.exclude(analysis_status=VideoClip.STATUS_PROCESSING).order_by('created_at')[:limit]
        clip_ids = list(qs.values_list('id', flat=True))

        if not clip_ids:
            self.stdout.write(self.style.SUCCESS('No missing-script clips found in selected window.'))
            return

        self.stdout.write(f'Found {len(clip_ids)} clips to recover. Running with {workers} workers...')
        ok = 0
        failed = 0
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {executor.submit(process_video_clip_now, cid): cid for cid in clip_ids}
            for future in as_completed(futures):
                cid = futures[future]
                try:
                    future.result()
                    ok += 1
                except Exception as exc:
                    failed += 1
                    self.stderr.write(f'Clip {cid} failed: {exc}')

        self.stdout.write(
            self.style.SUCCESS(
                f'Recovery completed. Success: {ok}, Failed: {failed}, Total: {len(clip_ids)}'
            )
        )
