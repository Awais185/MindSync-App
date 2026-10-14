"""
Run periodic background repair workers (video chunks + facial OpenFace).

Usage:
    python manage.py run_background_workers
    python manage.py run_background_workers --every-seconds 60
"""

from __future__ import annotations

import subprocess
import sys
import time

from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Run video chunk backfill + facial expression OpenFace workers every N seconds.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--every-seconds',
            type=int,
            default=60,
            help='Interval between runs (default: 60).',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=50,
            help='Max rows per worker per tick.',
        )

    def handle(self, *args, **options):
        every = max(30, int(options['every_seconds']))
        limit = max(1, int(options['limit']))
        self.stdout.write(
            self.style.WARNING(
                f'Background workers started (every {every}s, limit={limit}). Ctrl+C to stop.'
            )
        )
        while True:
            self._run_worker('recover_incomplete_chunk_results', limit)
            self._run_worker('process_facial_expressions', limit)
            time.sleep(every)

    def _run_worker(self, name: str, limit: int) -> None:
        cmd = [sys.executable, 'manage.py', name, '--limit', str(limit)]
        try:
            subprocess.run(cmd, check=False, timeout=600)
        except Exception as exc:
            self.stderr.write(f'{name} failed: {exc}')
