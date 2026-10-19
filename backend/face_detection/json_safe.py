"""Make API payloads JSON-serializable (no NaN / Inf)."""

from __future__ import annotations

import math
from numbers import Real
from typing import Any


def finite_float(value: Any, default: float = 0.0) -> float:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(f):
        return default
    return f


def json_safe_payload(obj: Any) -> Any:
    if obj is None or isinstance(obj, (str, bool, int)):
        return obj
    if isinstance(obj, Real) and not isinstance(obj, bool):
        f = float(obj)
        if not math.isfinite(f):
            return None
        return f
    if isinstance(obj, dict):
        return {str(k): json_safe_payload(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [json_safe_payload(v) for v in obj]
    return obj
