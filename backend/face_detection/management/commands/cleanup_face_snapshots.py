from __future__ import annotations

import os

from django.core.management.base import BaseCommand
from django.utils import timezone

from face_detection.models import FaceSnapshot


class Command(BaseCommand):
    help = "Delete expired face snapshot images and DB rows."

    def handle(self, *args, **options):
        now = timezone.now()
        qs = FaceSnapshot.objects.filter(expires_at__lte=now).only("id", "image")

        deleted = 0
        for snap in qs.iterator():
            try:
                if snap.image and snap.image.name:
                    # Delete file from storage
                    snap.image.delete(save=False)
            except Exception:
                pass
            deleted += 1

        # Delete rows after attempting storage cleanup
        qs.delete()
        self.stdout.write(self.style.SUCCESS(f"Deleted {deleted} expired snapshots."))

