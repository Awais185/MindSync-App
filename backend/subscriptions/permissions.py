from __future__ import annotations

from functools import wraps

from rest_framework.response import Response
from rest_framework import status

from .services import SubscriptionService


def require_subscription_feature(
    feature_key: str,
    upgrade_message: str = 'Upgrade your plan to access this feature.',
):
    """
    Decorator for APIView methods to block premium access when current
    subscription plan does not include the requested feature.
    """

    def decorator(view_method):
        @wraps(view_method)
        def wrapper(view, request, *args, **kwargs):
            if not request.user or not request.user.is_authenticated:
                return Response(
                    {'message': 'Authentication required.'},
                    status=status.HTTP_401_UNAUTHORIZED,
                )
            if SubscriptionService.can_access_feature(request.user, feature_key):
                return view_method(view, request, *args, **kwargs)
            return Response(
                {
                    'message': upgrade_message or 'Upgrade your plan to access this feature.',
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        return wrapper

    return decorator
