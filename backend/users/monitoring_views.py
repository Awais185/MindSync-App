"""Configurable social-app targets for Android background monitoring."""

from __future__ import annotations

import json
import os

from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView


DEFAULT_TARGET_APPS: list[dict[str, str]] = [
    {"package_name": "com.instagram.android", "app_name": "Instagram"},
    {"package_name": "com.whatsapp", "app_name": "WhatsApp"},
    {"package_name": "com.facebook.katana", "app_name": "Facebook"},
    {"package_name": "com.zhiliaoapp.musically", "app_name": "TikTok"},
    {"package_name": "com.ss.android.ugc.trill", "app_name": "TikTok"},
    {"package_name": "com.snapchat.android", "app_name": "Snapchat"},
    {"package_name": "org.telegram.messenger", "app_name": "Telegram"},
    {"package_name": "com.twitter.android", "app_name": "X"},
    {"package_name": "com.x.android", "app_name": "X"},
    {"package_name": "com.google.android.youtube", "app_name": "YouTube"},
]


def _load_target_apps() -> list[dict[str, str]]:
    raw = (os.environ.get("MONITORED_TARGET_APPS_JSON") or "").strip()
    if not raw:
        return list(DEFAULT_TARGET_APPS)
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            out: list[dict[str, str]] = []
            for row in data:
                if isinstance(row, str) and row.strip():
                    out.append({"package_name": row.strip(), "app_name": row.strip()})
                elif isinstance(row, dict):
                    pkg = str(row.get("package_name") or row.get("package") or "").strip()
                    if pkg:
                        out.append(
                            {
                                "package_name": pkg,
                                "app_name": str(
                                    row.get("app_name") or row.get("name") or pkg
                                ).strip()[:120],
                            }
                        )
            if out:
                return out
    except json.JSONDecodeError:
        pass
    return list(DEFAULT_TARGET_APPS)


class MonitoredTargetAppsAPIView(APIView):
    """
    GET /api/auth/monitoring/target-apps/
    Returns packages that trigger screen (30s) + face (20s / 5min) monitoring on device.
    """

    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        apps = _load_target_apps()
        packages = [a["package_name"] for a in apps]
        return Response(
            {
                "apps": apps,
                "packages": packages,
                "version": 1,
            }
        )
