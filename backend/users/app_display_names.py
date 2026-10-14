"""Normalize app labels from package names / stored telemetry for APIs and lists."""

from __future__ import annotations

from django.db.models import OuterRef, Subquery, Sum

# Short, user-visible names for packages that otherwise show long OEM strings or internal IDs.
CANONICAL_DISPLAY_NAMES: dict[str, str] = {
    'com.google.android.youtube': 'YouTube',
    'com.google.android.apps.youtube.music': 'YouTube Music',
    'com.google.android.googlequicksearchbox': 'Google',
    'com.google.android.apps.searchlite': 'Google',
    'com.android.chrome': 'Chrome',
    'com.chrome.beta': 'Chrome Beta',
    'com.chrome.dev': 'Chrome Dev',
    'com.google.android.gm': 'Gmail',
    'com.google.android.apps.maps': 'Maps',
    'com.google.android.apps.messaging': 'Messages',
    'com.google.android.apps.photos': 'Photos',
    'com.google.android.apps.docs': 'Drive',
    'com.google.android.apps.docs.editors.docs': 'Docs',
    'com.google.android.apps.docs.editors.sheets': 'Sheets',
    'com.google.android.calendar': 'Calendar',
    'com.google.android.contacts': 'Contacts',
    'com.google.android.dialer': 'Phone',
    'com.android.dialer': 'Phone',
    'com.google.android.apps.nbu.files': 'Files',
    'com.google.android.play.games': 'Play Games',
    'com.android.vending': 'Play Store',
    'com.google.android.apps.walletnfcrel': 'Wallet',
    'com.google.android.apps.subscriptions.red': 'Google One',
    'com.instagram.android': 'Instagram',
    'com.facebook.katana': 'Facebook',
    'com.facebook.orca': 'Messenger',
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.twitter.android': 'X',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.spotify.music': 'Spotify',
    'com.netflix.mediaclient': 'Netflix',
    'com.amazon.mShop.android.shopping': 'Amazon',
    'com.snapchat.android': 'Snapchat',
    'com.discord': 'Discord',
    'com.reddit.frontpage': 'Reddit',
    'com.microsoft.teams': 'Teams',
    'com.openai.chatgpt': 'ChatGPT',
}


def _looks_technical_label(label: str, package_name: str) -> bool:
    s = (label or '').strip()
    if not s:
        return True
    if s == package_name:
        return True
    low = s.lower()
    if 'activity' in low or 'service' in low or 'application' in low:
        return True
    if s.startswith(('com.', 'org.', 'net.')) and s.count('.') >= 2:
        return True
    if len(s) > 96:
        return True
    return False


def _title_from_package(package_name: str) -> str:
    base = package_name.split('.')[-1].replace('_', ' ').strip()
    if not base:
        return package_name
    return base.replace('-', ' ').title()


def display_app_name(package_name: str | None, stored_app_name: str | None) -> str:
    pkg = (package_name or '').strip()
    stored = (stored_app_name or '').strip()
    if not pkg:
        return stored or 'Unknown'
    if pkg in CANONICAL_DISPLAY_NAMES:
        return CANONICAL_DISPLAY_NAMES[pkg]
    if stored and not _looks_technical_label(stored, pkg):
        return stored
    return _title_from_package(pkg)


def rollup_screen_usage_apps(events_qs, latest_scope_qs):
    """
    Roll up usage by package_name with a single display name per package.

    events_qs: ScreenUsageEvent queryset (user + period already applied).
    latest_scope_qs: same logical scope, used to pick the most recent stored app_name.
    """
    stored_sq = Subquery(
        latest_scope_qs.filter(package_name=OuterRef('package_name'))
        .order_by('-end_time')
        .values('app_name')[:1]
    )
    rows = (
        events_qs.values('package_name')
        .annotate(total_seconds=Sum('usage_time'), _stored=stored_sq)
        .order_by('-total_seconds')
    )
    return [
        {
            'package_name': r['package_name'],
            'app_name': display_app_name(r['package_name'], r['_stored']),
            'usage_time': r['total_seconds'],
        }
        for r in rows
    ]
