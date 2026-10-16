"""
Pickle compatibility for MindSync depression joblib bundle.

The exported model wraps a sklearn MLPClassifier with a StandardScaler.
Training pickled ``BlockEarlyStopMLP`` from ``__main__``; register the same
class before ``joblib.load``.
"""

from __future__ import annotations

from sklearn.base import BaseEstimator, ClassifierMixin
from sklearn.preprocessing import StandardScaler


class BlockEarlyStopMLP(BaseEstimator, ClassifierMixin):
    """Thin wrapper restored from the training notebook export."""

    _estimator_type = "classifier"

    def __init__(
        self,
        hidden=(128, 64),
        alpha=0.0001,
        batch=256,
        epochs=200,
        seed=42,
    ):
        self.hidden = hidden
        self.alpha = alpha
        self.batch = batch
        self.epochs = epochs
        self.seed = seed
        self.scaler: StandardScaler | None = None
        self.sc_: StandardScaler | None = None
        self.net_ = None
        self.classes_ = None

    def _get_scaler(self) -> StandardScaler:
        scaler = getattr(self, "scaler", None) or getattr(self, "sc_", None)
        if scaler is None:
            raise RuntimeError("Depression model is not fitted.")
        return scaler

    def predict_proba(self, X):
        if self.net_ is None:
            raise RuntimeError("Depression model is not fitted.")
        Xs = self._get_scaler().transform(X)
        return self.net_.predict_proba(Xs)

    def predict(self, X):
        if self.net_ is None:
            raise RuntimeError("Depression model is not fitted.")
        Xs = self._get_scaler().transform(X)
        return self.net_.predict(Xs)
