"""
Process facial expression videos that are missing OpenFace AU results.

Usage:
    python manage.py process_facial_expressions
    python manage.py process_facial_expressions --random --limit 10
    python manage.py process_facial_expressions --all
"""

import time

from django.core.management.base import BaseCommand

from face_detection.facial_expression_service import (
    incomplete_facial_expression_queryset,
    process_all_incomplete_facial_captures,
    process_facial_expression_capture_sync,
    process_random_incomplete_batch,
)


class Command(BaseCommand):
    help = (
        "Run emotion model (+ OpenFace when available) on facial expression "
        "captures that have video but no results yet."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--limit",
            type=int,
            default=5,
            help="Max rows to process this run (default: 5)",
        )
        parser.add_argument(
            "--random",
            action="store_true",
            help="Pick incomplete rows in random order",
        )
        parser.add_argument(
            "--all",
            action="store_true",
            help="Process all incomplete rows (ignores --limit cap of 5 default)",
        )
        parser.add_argument(
            "--capture-id",
            type=int,
            default=None,
            help="Process a single capture id",
        )
        parser.add_argument(
            "--continuous",
            action="store_true",
            help="Run forever every --every-seconds (default 60).",
        )
        parser.add_argument(
            "--every-seconds",
            type=int,
            default=60,
            help="Interval for continuous mode.",
        )

    def handle(self, *args, **options):
        capture_id = options.get("capture_id")
        if capture_id:
            ok = process_facial_expression_capture_sync(int(capture_id))
            self.stdout.write(
                self.style.SUCCESS if ok else self.style.ERROR,
                f"Capture {capture_id}: {'ok' if ok else 'failed'}",
            )
            return

        if options.get("all"):
            stats = process_all_incomplete_facial_captures()
            self.stdout.write(
                self.style.SUCCESS(
                    f"Processed {stats['processed']}/{stats['total_candidates']} "
                    f"capture(s); {stats['remaining']} still incomplete."
                )
            )
            return

        if options.get("continuous"):
            every = max(30, int(options["every_seconds"]))
            limit = max(1, int(options["limit"]))
            self.stdout.write(
                self.style.WARNING(
                    f"Continuous facial processing every {every}s (limit={limit}). Ctrl+C to stop."
                )
            )
            while True:
                self._run_batch(limit, bool(options.get("random")))
                time.sleep(every)
            return

        limit = max(1, int(options["limit"]))
        self._run_batch(limit, bool(options.get("random")))

    def _run_batch(self, limit: int, random_order: bool) -> None:
        processed = process_random_incomplete_batch(
            limit=limit,
            random_order=random_order,
        )
        self.stdout.write(
            self.style.SUCCESS(f"Processed {processed} incomplete facial expression capture(s).")
        )

    def _incomplete_queryset(self):
        return incomplete_facial_expression_queryset()
