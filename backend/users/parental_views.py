"""
App blocking for the authenticated user (same account / device — no child linking).
"""

from django.contrib.auth.models import User
from django.db import transaction
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated

from .models import BlockedAppPackage, ChildReportedApp
from .parental_serializers import ParentBlockedAppWriteSerializer, ChildInstalledAppsReportSerializer
from subscriptions.permissions import require_subscription_feature


BLOCKED_PACKAGE_ALIAS_GROUPS = [
    {
        'com.zhiliaoapp.musically',
        'com.ss.android.ugc.trill',
        'com.zhiliaoapp.musically.go',
    },
    {'com.twitter.android', 'com.x.android'},
    {'com.whatsapp', 'com.whatsapp.w4b'},
]

def _expand_blocked_aliases(package_name: str) -> set[str]:
    pkg = (package_name or '').strip()
    if not pkg:
        return set()
    out = {pkg}
    for group in BLOCKED_PACKAGE_ALIAS_GROUPS:
        if pkg in group:
            out.update(group)
            break
    return out


def _merge_apps_for_user(user: User):
    """Union of reported apps and blocked rows with labels + blocked flags + dynamic categories."""
    reported = {r.package_name: r.app_label or r.package_name for r in ChildReportedApp.objects.filter(child_user=user)}
    blocked = {b.package_name: b.blocked for b in BlockedAppPackage.objects.filter(child_user=user)}
    labels = {}
    for pkg, lab in reported.items():
        labels[pkg] = lab
    all_pkgs = set(reported.keys()) | set(blocked.keys())
    for pkg in sorted(all_pkgs):
        lab = labels.get(pkg, pkg)
        is_blocked = blocked.get(pkg, False)
        
        # Simple auto-categorization based on package name heuristics
        pkg_lower = pkg.lower()
        category = 'Other'
        if any(x in pkg_lower for x in ['tiktok', 'instagram', 'facebook', 'twitter', 'snapchat', 'youtube', 'whatsapp', 'telegram', 'discord', 'musically', 'trill']):
            category = 'Social Media'
        elif any(x in pkg_lower for x in ['game', 'pubg', 'roblox', 'minecraft', 'candycrush', 'supercell']):
            category = 'Games'
        elif any(x in pkg_lower for x in ['netflix', 'hulu', 'disney', 'primevideo', 'hbo']):
            category = 'Entertainment'
            
        yield {'package_name': pkg, 'app_label': lab, 'blocked': is_blocked, 'category': category}


class ParentBlockedAppsAPIView(APIView):
    """List blockable apps + blocked state for the current user (Parent Control tab)."""

    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'parental_control',
        'Upgrade to Premium to access Parental Control.',
    )
    def get(self, request):
        user = request.user
        apps = list(_merge_apps_for_user(user))
        blocked_count = sum(1 for a in apps if a['blocked'])
        return Response(
            {
                'user_id': user.id,
                'apps': apps,
                'blocked_count': blocked_count,
            }
        )


class ParentBlockedAppUpdateAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'parental_control',
        'Upgrade to Premium to access Parental Control.',
    )
    def put(self, request):
        ser = ParentBlockedAppWriteSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        user = request.user
        pkg = ser.validated_data['package_name'].strip()
        blocked = ser.validated_data['blocked']
        alias_pkgs = sorted(_expand_blocked_aliases(pkg))
        with transaction.atomic():
            for alias_pkg in alias_pkgs:
                BlockedAppPackage.objects.update_or_create(
                    child_user=user,
                    package_name=alias_pkg,
                    defaults={'blocked': blocked},
                )
            obj = BlockedAppPackage.objects.get(child_user=user, package_name=pkg)
        return Response(
            {
                'package_name': obj.package_name,
                'blocked': obj.blocked,
                'updated_at': obj.updated_at.isoformat(),
            },
            status=status.HTTP_200_OK,
        )


class ChildBlockedPackagesAPIView(APIView):
    """Device polls this to enforce blocks locally."""

    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'parental_control',
        'Upgrade to Premium to access Parental Control.',
    )
    def get(self, request):
        qs = BlockedAppPackage.objects.filter(child_user=request.user, blocked=True).values_list(
            'package_name', flat=True
        )
        from django.utils import timezone

        return Response(
            {
                'blocked_packages': list(qs),
                'server_time': timezone.now().isoformat(),
            }
        )


class ParentContentMonitorAPIView(APIView):
    """Top watched content types from VideoChunkAnalysis for Parent Control."""

    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'parental_control',
        'Upgrade to Premium to access Parental Control.',
    )
    def get(self, request):
        from users.services.behavioral_insights_analytics import build_parent_content_monitor

        return Response(build_parent_content_monitor(request.user))


class ChildInstalledAppsReportAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'parental_control',
        'Upgrade to Premium to access Parental Control.',
    )
    def post(self, request):
        ser = ChildInstalledAppsReportSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        user = request.user
        with transaction.atomic():
            for item in ser.validated_data['apps']:
                pkg = item['package_name'].strip()
                label = (item.get('app_label') or '').strip() or pkg
                ChildReportedApp.objects.update_or_create(
                    child_user=user,
                    package_name=pkg,
                    defaults={'app_label': label},
                )
        return Response({'ok': True, 'count': len(ser.validated_data['apps'])})
