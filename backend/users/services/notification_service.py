"""Create and dedupe in-app user notifications."""

from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from users.models import UserNotification


def _create_if_new(
    user,
    *,
    event_type: str,
    title: str,
    body: str,
    dedupe_key: str,
    action_route: str = '',
    action_label: str = '',
    priority: int = 0,
) -> bool:
    if dedupe_key:
        exists = UserNotification.objects.filter(
            user=user,
            dedupe_key=dedupe_key,
        ).exists()
        if exists:
            return False
    UserNotification.objects.create(
        user=user,
        event_type=event_type,
        title=title,
        body=body,
        dedupe_key=dedupe_key,
        action_route=action_route,
        action_label=action_label,
        priority=priority,
    )
    return True


def notify_welcome(user) -> bool:
    return _create_if_new(
        user,
        event_type=UserNotification.EVENT_WELCOME,
        title='Welcome to MindSync!',
        body=(
            'Your wellbeing journey starts here. Explore your Mind Balance Index, '
            'track screen time, and check in with your mental health insights.'
        ),
        dedupe_key='welcome',
        action_route='home',
        action_label='Open Home',
        priority=1,
    )


def notify_weekly_report_ready(user) -> bool:
    week_key = timezone.localdate().strftime('%G-W%V')
    return _create_if_new(
        user,
        event_type=UserNotification.EVENT_WEEKLY_REPORT,
        title='Weekly report',
        body='Your weekly report is ready! Check it out.',
        dedupe_key=f'weekly_report:{week_key}',
        action_route='weekly_report',
        action_label='View report',
        priority=2,
    )


def notify_password_reset_requested(user) -> bool:
    stamp = timezone.now().strftime('%Y-%m-%dT%H')
    return _create_if_new(
        user,
        event_type=UserNotification.EVENT_PASSWORD_RESET_REQUESTED,
        title='Password reset requested',
        body=(
            'A password reset was requested for your MindSync account. '
            'If this was not you, secure your email and contact support.'
        ),
        dedupe_key=f'password_reset_req:{stamp}',
        action_route='profile',
        action_label='Account settings',
        priority=3,
    )


def notify_password_changed(user) -> bool:
    stamp = timezone.now().strftime('%Y-%m-%dT%H')
    return _create_if_new(
        user,
        event_type=UserNotification.EVENT_PASSWORD_CHANGED,
        title='Password changed successfully',
        body='Your MindSync password was updated. You can sign in with your new password.',
        dedupe_key=f'password_changed:{stamp}',
        action_route='profile',
        action_label='Account settings',
        priority=3,
    )


def notify_low_wellbeing(user, score: int) -> bool:
    day = timezone.localdate().isoformat()
    return _create_if_new(
        user,
        event_type=UserNotification.EVENT_LOW_WELLBEING,
        title='Well-being check-in',
        body=(
            f'Your well-being score is {score}/100 — below 40%. '
            'Try a short break, breathing exercise, or earlier wind-down tonight.'
        ),
        dedupe_key=f'low_wellbeing:{day}',
        action_route='recommendations',
        action_label='Habit guidance',
        priority=5,
    )


def run_automatic_triggers(user) -> int:
    """Welcome (once), weekly report (per ISO week), low wellbeing (daily if score < 40)."""
    created = 0
    if notify_welcome(user):
        created += 1

    last_weekly = (
        UserNotification.objects.filter(
            user=user,
            event_type=UserNotification.EVENT_WEEKLY_REPORT,
        )
        .order_by('-created_at')
        .first()
    )
    if last_weekly is None or timezone.now() - last_weekly.created_at >= timedelta(days=7):
        if notify_weekly_report_ready(user):
            created += 1

    try:
        from users.wellbeing import build_wellness_dashboard

        dash = build_wellness_dashboard(user, days=7)
        score = int(dash.get('wellbeing_score') or 0)
        if score > 0 and score < 40:
            if notify_low_wellbeing(user, score):
                created += 1
    except Exception:
        pass

    return created


def serialize_notification(n: UserNotification) -> dict:
    return {
        'id': n.id,
        'event_type': n.event_type,
        'title': n.title,
        'body': n.body,
        'action_route': n.action_route,
        'action_label': n.action_label,
        'priority': n.priority,
        'is_read': n.is_read,
        'created_at': n.created_at.isoformat(),
    }
