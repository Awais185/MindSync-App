from __future__ import annotations

import logging
import os
import pickle
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from django.db import close_old_connections
from django.utils import timezone

from users.models import VideoChunkAnalysis

logger = logging.getLogger(__name__)

_BEHAVIOR_EXECUTOR = ThreadPoolExecutor(
    max_workers=int(os.environ.get('BEHAVIOR_ANALYSIS_WORKERS', '4')),
    thread_name_prefix='behavior-analysis',
)


class EnsembleFinalBehaviorModel:
    def __init__(self) -> None:
        self._loaded = False
        self._load_error: str | None = None
        self._tokenizer = None
        self._model = None
        self._label_encoder = None
        self._labels: list[str] = []

    @property
    def model_dir(self) -> Path:
        default_dir = Path(__file__).resolve().parents[2] / 'behaviour medel' / 'ensemble_final_model'
        override = os.environ.get('ENSEMBLE_FINAL_MODEL_PATH', '').strip()
        return Path(override) if override else default_dir

    def _ensure_loaded(self) -> None:
        if self._loaded:
            return
        try:
            from transformers import AutoModelForSequenceClassification, AutoTokenizer
            import torch
        except Exception as exc:
            self._load_error = f'ML dependencies missing: {exc}'
            logger.exception('Behavior model dependencies missing')
            self._loaded = True
            return

        model_dir = self.model_dir
        model_path = model_dir / 'model_roberta'
        encoder_path = model_dir / 'label_encoder.pkl'
        try:
            self._tokenizer = AutoTokenizer.from_pretrained(str(model_path))
            self._model = AutoModelForSequenceClassification.from_pretrained(str(model_path))
            self._model.eval()
            self._label_encoder = self._load_label_encoder(encoder_path)
            classes = getattr(self._label_encoder, 'classes_', None)
            self._labels = [str(c) for c in classes] if classes is not None else []
            self._loaded = True
            logger.info('Loaded ensemble_final_model from %s', model_dir)
        except Exception as exc:
            self._load_error = str(exc)
            self._loaded = True
            logger.exception('Failed to load ensemble_final_model from %s', model_dir)

    def _load_label_encoder(self, encoder_path: Path):
        # label_encoder.pkl requires scikit-learn at unpickle time.
        try:
            import sklearn  # noqa: F401
        except ImportError as exc:
            raise RuntimeError(
                'scikit-learn is required for behavior detection. '
                'Install with: pip install scikit-learn joblib'
            ) from exc

        with open(encoder_path, 'rb') as f:
            raw_bytes = f.read()
        try:
            import joblib

            return joblib.load(str(encoder_path))
        except Exception:
            pass
        try:
            return pickle.loads(raw_bytes)
        except Exception:
            pass
        try:
            return pickle.loads(raw_bytes, encoding='latin1')
        except Exception as exc:
            raise RuntimeError(f'Unable to load label_encoder.pkl: {exc}') from exc

    def _fallback_prediction(self, reason: str) -> dict[str, Any]:
        return {
            'behavior_result': 'unavailable',
            'confidence_score': 0.0,
            'classification_outputs': {
                'model_name': 'ensemble_final_model',
                'fallback': True,
                'reason': reason[:500],
            },
        }

    def predict(self, text: str) -> dict[str, Any]:
        self._ensure_loaded()
        if self._load_error:
            return self._fallback_prediction(self._load_error)
        if not self._model or not self._tokenizer:
            return self._fallback_prediction('Model is not initialized')

        import torch

        inputs = self._tokenizer(
            text or '',
            truncation=True,
            max_length=256,
            return_tensors='pt',
        )
        with torch.no_grad():
            logits = self._model(**inputs).logits
            probs = torch.softmax(logits, dim=-1)[0].cpu().tolist()

        idx = max(range(len(probs)), key=lambda i: probs[i]) if probs else 0
        if self._labels and idx < len(self._labels):
            behavior = self._labels[idx]
        else:
            behavior = str(idx)

        labels = self._labels or [str(i) for i in range(len(probs))]
        probabilities = {
            labels[i]: float(probs[i]) for i in range(min(len(labels), len(probs)))
        }
        top_sorted = sorted(probabilities.items(), key=lambda kv: kv[1], reverse=True)[:5]
        return {
            'behavior_result': behavior,
            'confidence_score': float(probs[idx]) if probs else 0.0,
            'classification_outputs': {
                'model_name': 'ensemble_final_model',
                'probabilities': probabilities,
                'top_predictions': [
                    {'label': label, 'score': score} for label, score in top_sorted
                ],
            },
        }


_MODEL = EnsembleFinalBehaviorModel()


def predict_behavior_from_text(script_text: str) -> dict[str, Any]:
    try:
        return _MODEL.predict(script_text or '')
    except Exception as exc:
        logger.warning('Behavior prediction failed, using fallback: %s', exc)
        return _MODEL._fallback_prediction(str(exc))


def analyze_and_update_video_chunk(chunk_id: int) -> bool:
    """Run ensemble behavior model on script_text and persist results. Returns True on success."""
    close_old_connections()
    try:
        row = VideoChunkAnalysis.objects.filter(id=chunk_id).first()
        if not row:
            return False
        script = (row.script_text or '').strip()
        if not script:
            VideoChunkAnalysis.objects.filter(id=chunk_id).update(
                prediction_error='No script text to analyze.',
                behavior_analyzed_at=timezone.now(),
            )
            return False

        prediction = predict_behavior_from_text(script)
        classification_outputs = prediction.get('classification_outputs') or {}
        behavior_result = str(prediction.get('behavior_result') or '')
        prediction_error = ''
        if classification_outputs.get('fallback'):
            prediction_error = str(classification_outputs.get('reason') or 'Behavior model unavailable')[
                :4000
            ]

        row.behavior_result = behavior_result
        row.behavior_results = dict(prediction)
        row.confidence_score = float(prediction.get('confidence_score') or 0.0)
        row.classification_outputs = classification_outputs
        row.prediction_error = prediction_error
        row.behavior_analyzed_at = timezone.now()
        row.save(
            update_fields=[
                'behavior_result',
                'behavior_results',
                'confidence_score',
                'classification_outputs',
                'prediction_error',
                'behavior_analyzed_at',
            ]
        )
        logger.info(
            'Behavior model chunk_id=%s result=%s confidence=%.3f',
            chunk_id,
            behavior_result,
            row.confidence_score or 0.0,
        )
        return behavior_result not in ('', 'unavailable')
    except Exception as exc:
        logger.exception('Behavior prediction failed for chunk %s', chunk_id)
        VideoChunkAnalysis.objects.filter(id=chunk_id).update(
            prediction_error=str(exc)[:4000],
            behavior_analyzed_at=timezone.now(),
        )
        return False
    finally:
        close_old_connections()


def submit_video_chunk_behavior_analysis(chunk_id: int, *, sync: bool = False) -> None:
    if sync:
        analyze_and_update_video_chunk(chunk_id)
        return
    _BEHAVIOR_EXECUTOR.submit(analyze_and_update_video_chunk, chunk_id)
