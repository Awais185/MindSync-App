"""Lazy exports so Django URL checks do not import OpenCV until analysis runs."""

from __future__ import annotations

__all__ = ['ensure_pending_chunk_analysis', 'submit_video_clip_analysis']


def __getattr__(name: str):
    if name in __all__:
        from .video_analysis import (
            ensure_pending_chunk_analysis,
            submit_video_clip_analysis,
        )
        return {
            'ensure_pending_chunk_analysis': ensure_pending_chunk_analysis,
            'submit_video_clip_analysis': submit_video_clip_analysis,
        }[name]
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')
