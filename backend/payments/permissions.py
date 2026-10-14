from rest_framework.permissions import BasePermission

from subscriptions.services import SubscriptionService


class HasActiveSubscription(BasePermission):
    message = 'An active subscription is required.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return SubscriptionService.get_active_subscription(request.user) is not None

    # TODO: Apply HasActiveSubscription to premium-only API views when requested.
