"""Backfill mental state and 7-day reports for all users."""

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand

from users.services.mental_state_sync import refresh_user_tracking_snapshots


class Command(BaseCommand):
    help = 'Rebuild UserMentalState and UserWeeklyReport rows from stored sensor data.'

    def add_arguments(self, parser):
        parser.add_argument('--user-id', type=int, help='Only refresh a single user id')

    def handle(self, *args, **options):
        user_id = options.get('user_id')
        qs = User.objects.all()
        if user_id:
            qs = qs.filter(id=user_id)
        count = 0
        for user in qs.iterator():
            refresh_user_tracking_snapshots(user)
            count += 1
        self.stdout.write(self.style.SUCCESS(f'Refreshed tracking snapshots for {count} user(s).'))
