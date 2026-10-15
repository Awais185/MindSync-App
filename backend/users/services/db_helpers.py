"""DB concurrency helpers (SQLite lock retries; no-op on PostgreSQL)."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from typing import TypeVar

from django.db import connection
from django.db.utils import OperationalError

logger = logging.getLogger(__name__)

T = TypeVar('T')


def run_with_db_retry(
    fn: Callable[[], T],
    *,
    max_attempts: int = 6,
    base_delay: float = 0.08,
) -> T:
    """Retry on SQLite lock/busy only; PostgreSQL runs once."""
    if connection.vendor != 'sqlite':
        return fn()

    last_exc: OperationalError | None = None
    for attempt in range(max_attempts):
        try:
            return fn()
        except OperationalError as exc:
            last_exc = exc
            message = str(exc).lower()
            if 'locked' not in message and 'busy' not in message:
                raise
            if attempt + 1 >= max_attempts:
                break
            delay = base_delay * (2**attempt)
            logger.warning(
                'SQLite busy/locked — retry %s/%s in %.2fs',
                attempt + 1,
                max_attempts,
                delay,
            )
            time.sleep(delay)
    assert last_exc is not None
    raise last_exc


# Backward-compatible alias
run_with_sqlite_retry = run_with_db_retry
