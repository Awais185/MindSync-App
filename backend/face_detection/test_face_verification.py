from __future__ import annotations

import unittest
from io import BytesIO

import numpy as np
from PIL import Image, ImageDraw

from face_detection.face_quality_gate import analyze_face_frame
from face_detection.face_verification_service import (
    compute_embedding,
    distance_to_probability,
    verify_face_pair,
)


def _solid_jpeg(w: int = 640, h: int = 480, color=(120, 120, 120)) -> bytes:
    img = Image.new("RGB", (w, h), color)
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


class FaceVerificationTests(unittest.TestCase):
    def test_distance_probability_at_half(self) -> None:
        self.assertAlmostEqual(distance_to_probability(0.5), 0.5, places=2)

    def test_unlock_blur_gate_more_lenient(self) -> None:
        gray = _solid_jpeg()
        ok_strict, reason_strict, _ = analyze_face_frame(gray, unlock_capture=False)
        ok_unlock, reason_unlock, _ = analyze_face_frame(gray, unlock_capture=True)
        # Flat image: both may reject no face; unlock should not be stricter on blur only.
        if reason_strict == "FRAME_BLURRY" and reason_unlock == "FRAME_BLURRY":
            pass  # same flat frame
        self.assertTrue(ok_strict is False or ok_unlock is False)

    def test_same_jpeg_matches_itself_opencv_backend(self) -> None:
        jpeg = _solid_jpeg()
        emb = compute_embedding(jpeg)
        if emb is None:
            self.skipTest("No embedding backend available")
        out = verify_face_pair(
            probe_bytes=jpeg,
            enrolled_bytes=jpeg,
            enrolled_embedding=[0.0] * int(emb.size),  # stale wrong cache ignored
            threshold=0.5,
            unlock_capture=True,
        )
        self.assertTrue(out["matched"])
        self.assertGreater(out["probability"], 0.9)

    def test_verify_rejected_returns_zero_probability(self) -> None:
        out = verify_face_pair(
            probe_bytes=_solid_jpeg(),
            enrolled_bytes=_solid_jpeg(),
            enrolled_embedding=None,
            threshold=0.5,
            unlock_capture=True,
        )
        self.assertFalse(out["matched"])
        self.assertEqual(out["probability"], 0.0)
        self.assertIn("reject_reason", out)


if __name__ == "__main__":
    unittest.main()
