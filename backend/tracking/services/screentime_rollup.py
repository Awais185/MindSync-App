"""Daily → weekly → monthly rollups; single source of truth for screen time totals."""

from __future__ import annotations

from datetime import date, timedelta

from django.db.models import Sum
from django.utils import timezone

from tracking.models import ScreenTime, ScreenTimeMonthly, ScreenTimeSession, ScreenTimeWeekly


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _events_total_seconds(user, day: date) -> int:
    from users.models import ScreenUsageEvent

    total = (
        ScreenUsageEvent.objects.filter(user=user, date=day).aggregate(s=Sum('usage_time'))['s']
        or 0
    )
    return int(total)


def _session_total_seconds(user, day: date) -> int:
    ms = (
        ScreenTimeSession.objects.filter(user=user, date=day)
        .values_list('total_ms', flat=True)
        .first()
    )
    return int((ms or 0) // 1000)


def day_total_seconds(user, day: date) -> int:
    """
    Authoritative seconds for a calendar day:
    - Past finalized days: ScreenTime (24h rollup from usage events).
    - Otherwise: max(granular events, archived session ms from midnight save-day).
    """
    today = timezone.now().date()
    if day < today:
        st = ScreenTime.objects.filter(user=user, date=day, is_finalized=True).first()
        if st is not None:
            return int(st.total_screen_time)
        return max(_events_total_seconds(user, day), _session_total_seconds(user, day))

    return max(_events_total_seconds(user, day), _session_total_seconds(user, day))


def sync_session_row_for_day(user, day: date, total_seconds: int) -> None:
    ScreenTimeSession.objects.update_or_create(
        user=user,
        date=day,
        defaults={'total_ms': max(0, int(total_seconds)) * 1000},
    )


def sync_weekly_monthly_tables(user, today: date | None = None) -> None:
    """Recompute week + month aggregates from per-day totals (events + finalized rows)."""
    today = today or timezone.now().date()
    week_start = _week_start(today)
    week_days = (today - week_start).days + 1
    week_sec = sum(
        day_total_seconds(user, week_start + timedelta(days=i)) for i in range(week_days)
    )
    ScreenTimeWeekly.objects.update_or_create(
        user=user,
        week_start=week_start,
        defaults={'total_ms': week_sec * 1000},
    )

    month_start = today.replace(day=1)
    month_days = (today - month_start).days + 1
    month_sec = sum(
        day_total_seconds(user, month_start + timedelta(days=i)) for i in range(month_days)
    )
    ym = f'{today.year:04d}-{today.month:02d}'
    ScreenTimeMonthly.objects.update_or_create(
        user=user,
        year_month=ym,
        defaults={'total_ms': month_sec * 1000},
    )


def sync_today_from_events(user) -> None:
    """Call after granular usage chunks are stored."""
    today = timezone.now().date()
    total_sec = day_total_seconds(user, today)
    sync_session_row_for_day(user, today, total_sec)
    sync_screen_time_seconds_row(user, total_sec, day=today)
    sync_weekly_monthly_tables(user, today)


def roll_completed_day_into_weekly(user, completed_day: date, day_total_ms: int) -> None:
    """Persist completed local day ms and refresh week row."""
    event_sec = _events_total_seconds(user, completed_day)
    total_sec = max(int(day_total_ms // 1000), event_sec)
    sync_session_row_for_day(user, completed_day, total_sec)
    sync_screen_time_seconds_row(user, total_sec, day=completed_day)

    week_start = _week_start(completed_day)
    week_end = completed_day
    week_sec = 0
    d = week_start
    while d <= week_end:
        week_sec += day_total_seconds(user, d)
        d += timedelta(days=1)
    ScreenTimeWeekly.objects.update_or_create(
        user=user,
        week_start=week_start,
        defaults={'total_ms': week_sec * 1000},
    )
    sync_weekly_monthly_tables(user, completed_day)


def maybe_roll_weekly_to_monthly(user, today: date | None = None) -> bool:
    sync_weekly_monthly_tables(user, today)
    return True


def maybe_reset_monthly_after_30_days(user, today: date | None = None) -> bool:
    """Monthly totals accumulate via rollups; never zero archived data."""
    return False


def sync_screen_time_seconds_row(
    user,
    total_seconds: int,
    social_seconds: int = 0,
    video_seconds: int = 0,
    *,
    day: date | None = None,
) -> None:
    """Keep legacy ScreenTime (seconds) aligned with session tables for APIs."""
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
    """Single source of truth for Flutter home / analytics totals (matches usage APIs)."""
    today = timezone.now().date()
    week_start = _week_start(today)
    month_start = today.replace(day=1)

    today_sec = day_total_seconds(user, today)
    week_sec = sum(
        day_total_seconds(user, week_start + timedelta(days=i))
        for i in range((today - week_start).days + 1)
    )
    month_sec = sum(
        day_total_seconds(user, month_start + timedelta(days=i))
        for i in range((today - month_start).days + 1)
    )

    sync_screen_time_seconds_row(user, today_sec, day=today)
    sync_session_row_for_day(user, today, today_sec)
    sync_weekly_monthly_tables(user, today)

    today_row = ScreenTime.objects.filter(user=user, date=today).first()

    return {
        'date': today.isoformat(),
        'today_total_seconds': today_sec,
        'today_total_ms': today_sec * 1000,
        'week_total_seconds': week_sec,
        'week_total_ms': week_sec * 1000,
        'month_total_seconds': month_sec,
        'month_total_ms': month_sec * 1000,
        'social_media_seconds': int(today_row.social_media_time) if today_row else 0,
        'video_watch_seconds': int(today_row.video_watch_time) if today_row else 0,
    }
