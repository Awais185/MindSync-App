"""Daily → weekly → monthly rollups for ScreenTimeSession / Weekly / Monthly tables."""

from __future__ import annotations

from datetime import date, timedelta

from django.db.models import Sum
from django.utils import timezone

from tracking.models import ScreenTime, ScreenTimeMonthly, ScreenTimeSession, ScreenTimeWeekly


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def roll_completed_day_into_weekly(user, completed_day: date, day_total_ms: int) -> None:
    """After a calendar day ends, persist ms and add into the week's running weekly row."""
    if day_total_ms < 0:
        day_total_ms = 0
    ScreenTimeSession.objects.update_or_create(
        user=user,
        date=completed_day,
        defaults={'total_ms': day_total_ms},
    )
    week_start = _week_start(completed_day)
    week_sum = (
        ScreenTimeSession.objects.filter(
            user=user,
            date__gte=week_start,
            date__lte=completed_day,
        ).aggregate(s=Sum('total_ms'))['s']
        or 0
    )
    ScreenTimeWeekly.objects.update_or_create(
        user=user,
        week_start=week_start,
        defaults={'total_ms': week_sum},
    )


def maybe_roll_weekly_to_monthly(user, today: date | None = None) -> bool:
    """
    Recalculates the current month's total from ScreenTimeSession without deleting daily history.
    """
    today = today or timezone.now().date()
    ym = f'{today.year:04d}-{today.month:02d}'
    month_total = (
        ScreenTimeSession.objects.filter(
            user=user,
            date__year=today.year,
            date__month=today.month,
        ).aggregate(s=Sum('total_ms'))['s']
        or 0
    )
    ScreenTimeMonthly.objects.update_or_create(
        user=user,
        year_month=ym,
        defaults={'total_ms': month_total},
    )
    return True


def maybe_reset_monthly_after_30_days(user, today: date | None = None) -> bool:
    """Monthly totals accumulate via weekly rollups; never zero archived data."""
    return False


def sync_screen_time_seconds_row(
    user,
    total_seconds: int,
    social_seconds: int = 0,
    video_seconds: int = 0,
    *,
    day: date | None = None,
) -> None:
    """Keep legacy ScreenTime (seconds) aligned with RN session tables for APIs."""
    target_day = day or timezone.now().date()
    ScreenTime.objects.update_or_create(
        user=user,
        date=target_day,
        defaults={
            'total_screen_time': max(0, total_seconds),
            'social_media_time': max(0, social_seconds),
            'video_watch_time': max(0, video_seconds),
        },
    )


def summary_for_user(user) -> dict:
    """Single source of truth for Flutter home / analytics / app usage."""
    today = timezone.now().date()
    week_start = _week_start(today)
    ym = f'{today.year:04d}-{today.month:02d}'

    today_row, _ = ScreenTime.objects.get_or_create(
        user=user,
        date=today,
        defaults={
            'total_screen_time': 0,
            'social_media_time': 0,
            'video_watch_time': 0,
        },
    )

    today_session_ms = (
        ScreenTimeSession.objects.filter(user=user, date=today)
        .values_list('total_ms', flat=True)
        .first()
    )

    today_legacy_ms = int(today_row.total_screen_time) * 1000
    today_ms = max(today_legacy_ms, int(today_session_ms or 0))

    # Calendar week (Mon–today): live session rows + today's live total.
    week_ms = int(
        ScreenTimeSession.objects.filter(
            user=user,
            date__gte=week_start,
            date__lte=today,
        ).aggregate(s=Sum('total_ms'))['s']
        or 0
    )
    week_ms = max(week_ms, today_ms)

    # Archived monthly rollups are now exact representations of the current month.
    month_ms = int(
        ScreenTimeMonthly.objects.filter(user=user, year_month=ym)
        .values_list('total_ms', flat=True)
        .first()
        or 0
    )
    month_ms = max(month_ms, today_ms)

    return {
        'date': today.isoformat(),
        'today_total_seconds': today_ms // 1000,
        'today_total_ms': today_ms,
        'week_total_seconds': (week_ms // 1000),
        'week_total_ms': week_ms,
        'month_total_seconds': (month_ms // 1000),
        'month_total_ms': month_ms,
        'social_media_seconds': today_row.social_media_time,
        'video_watch_seconds': today_row.video_watch_time,
    }
