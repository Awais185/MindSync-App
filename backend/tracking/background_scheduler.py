"""
Auto-start video chunk recovery + facial OpenFace workers with Django runserver.

Disable with: MINDSYNC_DISABLE_AUTO_WORKERS=1

Intervals (seconds):
  MINDSYNC_VIDEO_RECOVERY_INTERVAL_SECONDS=120  (script + classification + behavior backfill)
  MINDSYNC_FACE_PROCESS_INTERVAL_SECONDS=300      (OpenFace AU processing)
"""

from __future__ import annotations

import logging
import os
import sys
import threading
import time

from django.db import connection
from django.db.utils import OperationalError

logger = logging.getLogger(__name__)


def _tracking_tables_ready() -> bool:
    try:
        tables = set(connection.introspection.table_names())
    except Exception:
        return False
    return 'tracking_videoclip' in tables

_started = False
_start_lock = threading.Lock()


def _should_autostart() -> bool:
    if os.environ.get('MINDSYNC_DISABLE_AUTO_WORKERS', '').strip().lower() in (
        '1',
        'true',
        'yes',
    ):
        return False

    argv = sys.argv
    skip_commands = (
        'migrate',
        'makemigrations',
        'test',
        'shell',
        'collectstatic',
        'createsuperuser',
        'recover_incomplete_chunk_results',
        'process_facial_expressions',
        'run_background_workers',
    )
    if any(cmd in argv for cmd in skip_commands):
        return False

    if 'runserver' in argv:
        if os.environ.get('RUN_MAIN') != 'true':
            return False
        return True

    return os.environ.get('MINDSYNC_AUTO_WORKERS', '').strip().lower() in (
        '1',
        'true',
        'yes',
    )


def _run_video_recovery_tick() -> None:
    if not _tracking_tables_ready():
        logger.debug(
            'backend_sync_service: skip video recovery — run python manage.py migrate',
        )
        return
    from tracking.management.commands.recover_incomplete_chunk_results import Command
    from tracking.services.incomplete_chunks import process_incomplete_chunks

    limit = max(1, int(os.environ.get('MINDSYNC_VIDEO_RECOVERY_LIMIT', '50')))
    workers = max(1, int(os.environ.get('MINDSYNC_VIDEO_RECOVERY_WORKERS', '4')))
    Command()._run_once(limit=limit, workers=workers)
    stats = process_incomplete_chunks(limit=limit)
    if stats.get('behavior_processed', 0) or stats.get('remaining_incomplete', 0):
        logger.info(
            'backend_sync_service: behavior backfill processed=%s remaining=%s',
            stats.get('behavior_processed'),
            stats.get('remaining_incomplete'),
        )


def _run_facial_expression_tick() -> None:
    if not _tracking_tables_ready():
        return
    try:
        tables = set(connection.introspection.table_names())
    except Exception:
        return
    if 'face_detection_facialexpressioncapture' not in tables:
        return
    from face_detection.facial_expression_service import process_random_incomplete_batch

    limit = max(1, int(os.environ.get('MINDSYNC_FACE_BATCH_LIMIT', '10')))
    process_random_incomplete_batch(limit=limit, random_order=False)


def _video_recovery_loop() -> None:
    interval = max(60, int(os.environ.get('MINDSYNC_VIDEO_RECOVERY_INTERVAL_SECONDS', '120')))
    logger.info(
        'backend_sync_service: video recovery every %ss (script, classification, behavior)',
        interval,
    )
    time.sleep(5)
    while True:
        try:
            _run_video_recovery_tick()
        except OperationalError as exc:
            if 'no such table' in str(exc).lower():
                logger.warning(
                    'backend_sync_service: database not migrated yet (%s); '
                    'run: python manage.py migrate',
                    exc,
                )
            else:
                logger.exception('backend_sync_service: video recovery tick failed')
        except Exception:
            logger.exception('backend_sync_service: video recovery tick failed')
        time.sleep(interval)


def _facial_expression_loop() -> None:
    interval = max(60, int(os.environ.get('MINDSYNC_FACE_PROCESS_INTERVAL_SECONDS', '300')))
    logger.info(
        'backend_sync_service: OpenFace facial processing every %ss',
        interval,
    )
    time.sleep(20)
    while True:
        try:
            _run_facial_expression_tick()
        except Exception:
            logger.exception('backend_sync_service: facial expression tick failed')
        time.sleep(interval)


def start_background_workers() -> None:
    global _started
    if not _should_autostart():
        return
    with _start_lock:
        if _started:
            return
        _started = True

    legacy = os.environ.get('MINDSYNC_WORKER_INTERVAL_SECONDS', '').strip()
    if legacy:
        logger.warning(
            'MINDSYNC_WORKER_INTERVAL_SECONDS is deprecated; use '
            'MINDSYNC_VIDEO_RECOVERY_INTERVAL_SECONDS and MINDSYNC_FACE_PROCESS_INTERVAL_SECONDS',
        )

    threading.Thread(
        target=_video_recovery_loop,
        name='mindsync-video-recovery',
        daemon=True,
    ).start()
    threading.Thread(
        target=_facial_expression_loop,
        name='mindsync-facial-openface',
        daemon=True,
    ).start()
