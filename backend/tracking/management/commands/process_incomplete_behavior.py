from django.core.management.base import BaseCommand

from tracking.services.incomplete_chunks import process_incomplete_chunks


class Command(BaseCommand):
    help = 'Find chunk analyses with script but no behavior_results; run ensemble behavior model.'

    def add_arguments(self, parser):
        parser.add_argument('--limit', type=int, default=100)

    def handle(self, *args, **options):
        limit = max(1, int(options['limit']))
        stats = process_incomplete_chunks(limit=limit)
        self.stdout.write(
            self.style.SUCCESS(
                f"clips_scanned={stats['clips_scanned']} "
                f"clips_repaired={stats['clips_repaired']} "
                f"behavior_processed={stats['behavior_processed']} "
                f"remaining={stats['remaining_incomplete']}"
            )
        )
