from datetime import datetime, timedelta, time
from django.utils import timezone
from django.db.models import Sum
from tracking.models import ScreenTime
from users.models import ScreenUsageEvent

def ensure_past_days_finalized(user):
    """
    Finds past days with ScreenUsageEvents that haven't been finalized in ScreenTime,
    and runs finalize_daily_usage for them.
    """
    today = timezone.now().date()
    # Find all distinct dates in ScreenUsageEvent for this user
    # that are strictly before today.
    past_dates_qs = ScreenUsageEvent.objects.filter(
        user=user, date__lt=today
    ).values_list('date', flat=True).distinct()
    
    # Find dates already finalized
    finalized_dates_qs = ScreenTime.objects.filter(
        user=user, is_finalized=True
    ).values_list('date', flat=True)
    
    finalized_dates = set(finalized_dates_qs)
    
    for d in past_dates_qs:
        if d not in finalized_dates:
            finalize_daily_usage(user, d)

def finalize_daily_usage(user, target_date):
    """
    Computes total active time, sleep time (screen OFF between 10 PM - 5 AM), 
    and late-night activity (screen ON between 10 PM - 5 AM) from ScreenUsageEvent.
    Marks the day as finalized in ScreenTime.
    """
    tz = timezone.get_current_timezone()
    
    # 24-hour boundaries
    day_start = timezone.make_aware(datetime.combine(target_date, time.min), tz)
    day_end = day_start + timedelta(days=1)
    
    # Calculate Total Active Screen Time for the 24-hour day
    events_day = ScreenUsageEvent.objects.filter(
        user=user,
        end_time__gte=day_start,
        end_time__lt=day_end
    )
    total_active_seconds = events_day.aggregate(t=Sum('usage_time'))['t'] or 0
    from tracking.services.screentime_rollup import _session_total_seconds

    stored = (
        ScreenTime.objects.filter(user=user, date=target_date)
        .values_list('total_screen_time', flat=True)
        .first()
        or 0
    )
    total_active_seconds = max(
        int(total_active_seconds),
        int(stored),
        _session_total_seconds(user, target_date),
    )

    # Sleep period: 10:00 PM of target_date to 5:00 AM of target_date + 1 day
    sleep_start = timezone.make_aware(datetime.combine(target_date, time(22, 0)), tz)
    sleep_end = timezone.make_aware(datetime.combine(target_date + timedelta(days=1), time(5, 0)), tz)
    
    # Active usage during sleep period (Late-Night Activity)
    events_night = ScreenUsageEvent.objects.filter(
        user=user,
        end_time__gt=sleep_start,
        start_time__lt=sleep_end
    )
    
    # We should precisely calculate overlap, but assuming usage_time roughly fits
    # inside the chunks, we can sum usage_time or compute overlap.
    # For simplicity, we calculate the overlap of each event with the sleep window.
    late_night_seconds = 0
    for ev in events_night:
        overlap_start = max(ev.start_time, sleep_start)
        overlap_end = min(ev.end_time, sleep_end)
        if overlap_end > overlap_start:
            late_night_seconds += int((overlap_end - overlap_start).total_seconds())

    # Sleep time is 7 hours (25200 seconds) minus late night activity
    total_sleep_window_seconds = 7 * 3600
    sleep_seconds = max(0, total_sleep_window_seconds - late_night_seconds)

    # Upsert the finalized data to ScreenTime
    st, _ = ScreenTime.objects.get_or_create(
        user=user,
        date=target_date,
        defaults={
            'total_screen_time': 0,
            'social_media_time': 0,
            'video_watch_time': 0,
        }
    )
    
    st.total_screen_time = total_active_seconds
    st.late_night_activity = late_night_seconds
    st.sleep_time = sleep_seconds
    st.is_finalized = True
    st.save()

    try:
        from tracking.services.screentime_rollup import (
            roll_completed_day_into_weekly,
            sync_weekly_monthly_tables,
        )

        roll_completed_day_into_weekly(user, target_date, total_active_seconds * 1000)
        sync_weekly_monthly_tables(user)
    except Exception:
        pass

    return st
