from django.core.management.base import BaseCommand

from subscriptions.services import SubscriptionService


class Command(BaseCommand):
    help = 'Expire active subscriptions older than end_date.'

    def handle(self, *args, **options):
        expired_count = SubscriptionService.expire_all_subscriptions()
        self.stdout.write(self.style.SUCCESS(f'Expired subscriptions: {expired_count}'))
