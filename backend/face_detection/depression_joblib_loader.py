"""Load the training joblib bundle without numpy 2.x RNG pickle compatibility."""

from __future__ import annotations

import sys
import types
from functools import lru_cache
from pathlib import Path
from typing import Any

import joblib
import numpy.random._pickle as _np_random_pickle

from django.conf import settings

from .adult_depression_inference import adult_depression_model_dir
from .depression_model_types import BlockEarlyStopMLP


class _DummyBitGenerator:
    def __setstate__(self, _state: object) -> None:
        return


def _install_pickle_compat() -> None:
    import numpy.random._mt19937 as _mt19937_mod

    _mt19937_mod.MT19937 = _DummyBitGenerator  # type: ignore[misc]

    def _bitgen_ctor(_name: object = "MT19937") -> _DummyBitGenerator:
        return _DummyBitGenerator()

    _np_random_pickle.__bit_generator_ctor = _bitgen_ctor
    _np_random_pickle.__randomstate_ctor = lambda *a, **k: __import__(
        "numpy"
    ).random.RandomState(42)

    mod = types.ModuleType("__main__")
    mod.BlockEarlyStopMLP = BlockEarlyStopMLP
    sys.modules["__main__"] = mod


@lru_cache(maxsize=1)
def load_depression_joblib_bundle() -> dict[str, Any]:
    _install_pickle_compat()
    path = adult_depression_model_dir() / "mindsync_depression_au_model.joblib"
    if not path.exists():
        raise FileNotFoundError(path)
    bundle = joblib.load(path)
    if not isinstance(bundle, dict) or "model" not in bundle:
        raise ValueError("Invalid depression model bundle")
    return bundle
