"""Debounce heavy UserWeeklyReport rebuilds to avoid SQLite write storms."""

from __future__ import annotations

import logging
import threading

from django.contrib.auth.models import User

from users.services.sqlite_helpers import run_with_sqlite_retry

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_timers: dict[int, threading.Timer] = {}

# Rolling report rebuild at most once per user per interval.
DEBOUNCE_SECONDS = 30


def schedule_weekly_report_rebuild(user_id: int) -> None:
    if not user_id:
        return

    def _run() -> None:
        with _lock:
            _timers.pop(user_id, None)
        try:
            user = User.objects.filter(id=user_id).first()
            if not user:
                return
            from users.services.weekly_report_builder import build_and_save_weekly_report

            run_with_sqlite_retry(lambda: build_and_save_weekly_report(user))
        except Exception:
            logger.exception('Debounced weekly report rebuild failed for user_id=%s', user_id)

    with _lock:
        existing = _timers.pop(user_id, None)
        if existing is not None:
            existing.cancel()
        timer = threading.Timer(DEBOUNCE_SECONDS, _run)
        timer.daemon = True
        _timers[user_id] = timer
        timer.start()
