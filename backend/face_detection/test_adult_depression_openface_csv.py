"""Depression MLP must consume OpenFace-style AU CSV (not raw video)."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import pandas as pd
from django.test import SimpleTestCase

from face_detection.adult_depression_inference import predict_openface_csv
from face_detection.openface_results import analyze_openface_csv


class AdultDepressionOpenFaceCsvTests(SimpleTestCase):
    def _feature_names(self) -> list[str]:
        card_path = (
            Path(__file__).resolve().parent.parent
            / "models"
            / "Adult depression detection"
            / "model"
            / "model_card.json"
        )
        if not card_path.is_file():
            self.skipTest("model_card.json not present")
        card = json.loads(card_path.read_text(encoding="utf-8"))
        return list(card["features"])

    def test_openface_csv_path_returns_screening_label(self):
        features = self._feature_names()
        rows = 30
        data = {col: [0.15] * rows for col in features}
        data["success"] = [1.0] * rows
        data["timestamp"] = [i / 25.0 for i in range(rows)]
        df = pd.DataFrame(data)

        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            csv_path = tmp.name
        try:
            df.to_csv(csv_path, index=False)
            via_helper = analyze_openface_csv(csv_path, use_depression_model=True)
            via_direct = predict_openface_csv(csv_path)
        finally:
            Path(csv_path).unlink(missing_ok=True)

        label = via_helper["depression_model"]["predicted_label"]
        self.assertIn(label, {"Healthy", "Mild", "Moderate", "Severe"})
        self.assertEqual(
            via_helper["depression_model"].get("input_source"),
            "openface_csv",
        )
        self.assertEqual(
            via_direct["depression_model"]["predicted_label"],
            label,
        )
        self.assertEqual(via_helper["analysis_source"], "adult_depression_mlp")
