from __future__ import annotations

import unittest
from unittest.mock import patch

from face_detection.au_emotion_pipeline import (
    analyze_frame,
    compute_scores,
    compute_visibility,
    normalize_aus,
)


class AuEmotionPipelineTests(unittest.TestCase):
    def test_whitespace_normalization(self) -> None:
        raw = {" AU04": 2.5, " AU01": 1.2}
        self.assertEqual(normalize_aus(raw), {"AU04": 2.5, "AU01": 1.2})

    def test_non_zero_scores_and_dominant(self) -> None:
        raw = {"AU04": 3.0, "AU06": 2.0, "AU15": 1.5}
        aus = normalize_aus(raw)
        scores = compute_scores(aus)
        self.assertGreater(scores["stress"], 0.0)
        self.assertGreater(scores["depression"], 0.0)
        with patch("face_detection.au_emotion_pipeline.print"):
            out = analyze_frame(raw)
        self.assertNotEqual(out["dominant_state"], "neutral")

    def test_visibility_floor(self) -> None:
        # Tracked AUs always yield a positive share; never the old "always 0" bug.
        self.assertGreater(compute_visibility(normalize_aus({"AU04": 1.0})), 0.0)
        # No overlap with EXPECTED_AUS → raw ratio 0 → minimum floor 0.1
        self.assertGreaterEqual(
            compute_visibility(normalize_aus({"AU08": 1.0})),
            0.1,
        )

    def test_empty_input(self) -> None:
        with patch("face_detection.au_emotion_pipeline.print"):
            out = analyze_frame({})
        self.assertEqual(out["stress_score"], 0.0)
        self.assertEqual(out["anxiety_score"], 0.0)
        self.assertEqual(out["depression_score"], 0.0)
        self.assertEqual(out["dominant_state"], "neutral")
        self.assertEqual(out["face_visibility_ratio"], 0.0)

    def test_matched_aus_by_state(self) -> None:
        with patch("face_detection.au_emotion_pipeline.print"):
            out = analyze_frame({"AU04": 2.0, "AU12": 1.5})
        matched = out["matched_aus_by_state"]
        self.assertEqual(matched["stress"]["AU04"], 2.0)
        self.assertEqual(matched["depression"]["AU12"], 1.5)

    def test_no_face_logs_no_crash(self) -> None:
        with patch("face_detection.au_emotion_pipeline.print") as mock_print:
            analyze_frame({})
        msgs = [str(a[0]) for a in mock_print.call_args_list if a.args]
        self.assertTrue(any("NO FACE" in m for m in msgs))


if __name__ == "__main__":
    unittest.main()
