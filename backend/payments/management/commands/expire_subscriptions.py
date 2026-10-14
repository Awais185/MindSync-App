from django.core.management.base import BaseCommand

from subscriptions.services import SubscriptionService


class Command(BaseCommand):
    help = 'Expire subscriptions past their expiry date'

    def handle(self, *args, **kwargs):
        count = SubscriptionService.expire_all_subscriptions()
        self.stdout.write(f'Expired {count} subscriptions')
