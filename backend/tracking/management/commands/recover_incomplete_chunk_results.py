from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from django.core.management.base import BaseCommand
from django.db.models import Q

from tracking.models import VideoClip
from tracking.services.incomplete_chunks import find_incomplete_clip_ids
from tracking.services.video_analysis import backfill_incomplete_clip_results
from users.models import VideoChunkAnalysis


class Command(BaseCommand):
    help = (
        'Check DB for incomplete chunk outputs and backfill missing '
        'script/content_type/behavior_result using pipeline models.'
    )

    def add_arguments(self, parser):
        parser.add_argument('--limit', type=int, default=1000, help='Max clips to repair.')
        parser.add_argument(
            '--workers',
            type=int,
            default=max(4, min(16, (os.cpu_count() or 4) * 2)),
            help='Parallel worker count.',
        )
        parser.add_argument(
            '--continuous',
            action='store_true',
            help='Run forever and check/fix incomplete clips repeatedly.',
        )
        parser.add_argument(
            '--every-seconds',
            type=int,
            default=60,
            help='Interval for continuous mode in seconds (default: 60).',
        )

    def _run_once(self, *, limit: int, workers: int) -> None:
        clip_ids = find_incomplete_clip_ids(limit=limit)

        if not clip_ids:
            self.stdout.write(self.style.SUCCESS('No incomplete chunk records found.'))
            return

        self.stdout.write(f'Found {len(clip_ids)} incomplete clips. Processing with {workers} workers...')
        script_filled = 0
        content_filled = 0
        behavior_filled = 0
        failed = 0

        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {executor.submit(backfill_incomplete_clip_results, cid): cid for cid in clip_ids}
            for future in as_completed(futures):
                cid = futures[future]
                try:
                    result = future.result()
                    if result.get('script_filled'):
                        script_filled += 1
                    if result.get('content_type_filled'):
                        content_filled += 1
                    if result.get('behavior_filled'):
                        behavior_filled += 1
                except Exception as exc:
                    failed += 1
                    self.stderr.write(f'Clip {cid} failed: {exc}')

        self.stdout.write(
            self.style.SUCCESS(
                f'Backfill complete: total={len(clip_ids)}, '
                f'script_filled={script_filled}, '
                f'content_type_filled={content_filled}, '
                f'behavior_filled={behavior_filled}, failed={failed}'
            )
        )

        # Quick post-check count
        from tracking.services.incomplete_chunks import incomplete_analysis_queryset

        remaining = incomplete_analysis_queryset().count()
        self.stdout.write(f'Remaining incomplete VideoChunkAnalysis rows: {remaining}')

    def handle(self, *args, **options):
        limit = max(1, int(options['limit']))
        workers = max(1, int(options['workers']))
        continuous = bool(options['continuous'])
        every_seconds = max(10, int(options['every_seconds']))

        if not continuous:
            self._run_once(limit=limit, workers=workers)
            return

        self.stdout.write(
            self.style.WARNING(
                f'Continuous mode started: checking every {every_seconds} seconds '
                f'(limit={limit}, workers={workers}). Press Ctrl+C to stop.'
            )
        )
        while True:
            self._run_once(limit=limit, workers=workers)
            time.sleep(every_seconds)
