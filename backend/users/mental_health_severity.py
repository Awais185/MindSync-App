"""Rule-based severity labels for mental health percentage scores (0–100)."""

from __future__ import annotations


def severity_label_from_percent(score: float | int | None) -> str:
    """Map 0–100 score to Normal / Mild / Moderate / High."""
    if score is None:
        return 'No data'
    s = float(score)
    if s < 0:
        s = 0.0
    if s > 100:
        s = 100.0
    if s >= 85:
        return 'High'
    if s >= 70:
        return 'Moderate'
    if s >= 50:
        return 'Mild'
    return 'Normal'


def severity_color_hex(score: float | int | None) -> str:
    label = severity_label_from_percent(score)
    return {
        'Normal': '#43A047',
        'Mild': '#FBC02D',
        'Moderate': '#FF9800',
        'High': '#E53935',
        'No data': '#9E9E9E',
    }.get(label, '#43A047')
