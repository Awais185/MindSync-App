from django.shortcuts import get_object_or_404
from rest_framework import permissions, response, status, views

from users.models import UserNotification
from users.services.notification_service import (
    notify_parent_bedtime,
    notify_parent_wakeup,
    run_automatic_triggers,
    serialize_notification,
)


class NotificationListAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        base = UserNotification.objects.filter(user=request.user)
        unread = base.filter(is_read=False).count()
        qs = base.order_by('-created_at')[:200]
        return response.Response(
            {
                'notifications': [serialize_notification(n) for n in qs],
                'unread_count': unread,
            }
        )


class NotificationUnreadCountAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        count = UserNotification.objects.filter(user=request.user, is_read=False).count()
        return response.Response({'unread_count': count})


class NotificationDetailAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request, notification_id: int):
        n = get_object_or_404(UserNotification, pk=notification_id, user=request.user)
        if not n.is_read:
            n.is_read = True
            n.save(update_fields=['is_read'])
        return response.Response(serialize_notification(n))


class NotificationMarkAllReadAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        updated = UserNotification.objects.filter(
            user=request.user,
            is_read=False,
        ).update(is_read=True)
        return response.Response({'ok': True, 'marked_read': updated})


class NotificationBulkDeleteAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        raw_ids = request.data.get('ids') or []
        ids = []
        for x in raw_ids:
            try:
                ids.append(int(x))
            except (TypeError, ValueError):
                continue
        if not ids:
            return response.Response(
                {'detail': 'Provide ids to delete.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        deleted, _ = UserNotification.objects.filter(
            user=request.user,
            id__in=ids,
        ).delete()
        return response.Response({'ok': True, 'deleted': deleted})


class ParentScheduleNotificationAPIView(views.APIView):
    """Bedtime / wake-up reminders from the device schedule."""

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        kind = (request.data.get('kind') or '').strip().lower()
        if kind == 'bedtime':
            created = notify_parent_bedtime(request.user)
        elif kind == 'wakeup':
            created = notify_parent_wakeup(request.user)
        else:
            return response.Response(
                {'detail': 'kind must be bedtime or wakeup.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return response.Response({'ok': True, 'created': created})


class NotificationSyncTriggersAPIView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        created = run_automatic_triggers(request.user)
        unread = UserNotification.objects.filter(
            user=request.user,
            is_read=False,
        ).count()
        return response.Response({'created': created, 'unread_count': unread})
