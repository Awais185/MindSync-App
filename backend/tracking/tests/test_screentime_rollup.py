from __future__ import annotations

from datetime import datetime, timedelta

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone

from tracking.models import ScreenTime, ScreenTimeMonthly, ScreenTimeSession, ScreenTimeWeekly
from tracking.services.screentime_rollup import (
    day_total_seconds,
    roll_completed_day_into_weekly,
    summary_for_user,
    sync_today_from_events,
)
from users.models import ScreenUsageEvent


class ScreenTimeRollupTests(TestCase):
    def setUp(self) -> None:
        self.user = User.objects.create_user(username="rollup_u", password="x")

    def test_day_total_prefers_finalized_past_day(self) -> None:
        yesterday = timezone.now().date() - timedelta(days=1)
        ScreenTime.objects.create(
            user=self.user,
            date=yesterday,
            total_screen_time=3600,
            is_finalized=True,
        )
        self.assertEqual(day_total_seconds(self.user, yesterday), 3600)

    def test_save_day_updates_week_and_month(self) -> None:
        yesterday = timezone.now().date() - timedelta(days=1)
        roll_completed_day_into_weekly(self.user, yesterday, 7_200_000)
        week_start = yesterday - timedelta(days=yesterday.weekday())
        week = ScreenTimeWeekly.objects.get(user=self.user, week_start=week_start)
        self.assertEqual(week.total_ms, 7_200_000)
        ym = f'{yesterday.year:04d}-{yesterday.month:02d}'
        month = ScreenTimeMonthly.objects.get(user=self.user, year_month=ym)
        self.assertGreaterEqual(month.total_ms, 7_200_000)

    def test_events_sync_updates_summary(self) -> None:
        today = timezone.now().date()
        tz = timezone.get_current_timezone()
        start = timezone.make_aware(datetime.combine(today, datetime.min.time()), tz)
        ScreenUsageEvent.objects.create(
            user=self.user,
            app_name="Test",
            package_name="com.test",
            usage_time=120,
            date=today,
            start_time=start,
            end_time=start + timedelta(seconds=120),
        )
        sync_today_from_events(self.user)
        summary = summary_for_user(self.user)
        self.assertGreaterEqual(summary['today_total_seconds'], 120)
        session = ScreenTimeSession.objects.get(user=self.user, date=today)
        self.assertGreaterEqual(session.total_ms, 120_000)
