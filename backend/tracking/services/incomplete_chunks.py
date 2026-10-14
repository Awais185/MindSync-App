"""Find and repair VideoChunkAnalysis rows missing behavior model output."""

from __future__ import annotations

import logging
from typing import Iterable

from django.db.models import Q

from tracking.models import VideoClip
from tracking.services.behavior_analysis import analyze_and_update_video_chunk
from tracking.services.video_analysis import backfill_incomplete_clip_results
from users.models import VideoChunkAnalysis

logger = logging.getLogger(__name__)


def incomplete_analysis_queryset():
    """Rows with script text but no behavior prediction saved yet."""
    return VideoChunkAnalysis.objects.filter(
        Q(script_text__isnull=False) & ~Q(script_text=''),
    ).filter(
        Q(behavior_result__isnull=True)
        | Q(behavior_result='')
        | Q(behavior_result='unavailable')
        | Q(behavior_analyzed_at__isnull=True)
        | Q(behavior_results__isnull=True)
        | Q(behavior_results={})
    )


def find_incomplete_chunk_analysis_ids(*, limit: int = 500) -> list[int]:
    return list(
        incomplete_analysis_queryset()
        .order_by('created_at')
        .values_list('id', flat=True)[:limit]
    )


def find_incomplete_clip_ids(*, limit: int = 500) -> list[int]:
    """Clips missing script, classification, and/or behavior on linked analysis."""
    return list(
        VideoClip.objects.filter(
            Q(script_text__isnull=True)
            | Q(script_text='')
            | Q(content_type__isnull=True)
            | Q(content_type={})
            | Q(analysis_records__isnull=True)
            | Q(analysis_records__script_text__isnull=True)
            | Q(analysis_records__script_text='')
            | Q(analysis_records__behavior_result__isnull=True)
            | Q(analysis_records__behavior_result='')
            | Q(analysis_records__behavior_results__isnull=True)
            | Q(analysis_records__behavior_results={})
        )
        .distinct()
        .order_by('created_at')
        .values_list('id', flat=True)[:limit]
    )


def run_behavior_on_chunk_ids(chunk_ids: Iterable[int]) -> int:
    """Send existing script_text through ensemble behavior model; return count processed."""
    processed = 0
    for chunk_id in chunk_ids:
        try:
            analyze_and_update_video_chunk(int(chunk_id))
            processed += 1
        except Exception:
            logger.exception('Behavior analysis failed for chunk %s', chunk_id)
    return processed


def process_incomplete_chunks(*, limit: int = 100) -> dict[str, int]:
    """
    1) Backfill clips missing vision/script pipeline pieces.
    2) Run behavior model on any analysis row that still has script but no behavior.
    """
    clip_ids = find_incomplete_clip_ids(limit=limit)
    backfill_ok = 0
    for clip_id in clip_ids:
        try:
            result = backfill_incomplete_clip_results(clip_id)
            if any(result.values()):
                backfill_ok += 1
        except Exception:
            logger.exception('Backfill failed for clip %s', clip_id)

    analysis_ids = find_incomplete_chunk_analysis_ids(limit=limit)
    behavior_ok = run_behavior_on_chunk_ids(analysis_ids)
    remaining = incomplete_analysis_queryset().count()
    return {
        'clips_scanned': len(clip_ids),
        'clips_repaired': backfill_ok,
        'behavior_processed': behavior_ok,
        'remaining_incomplete': remaining,
    }
