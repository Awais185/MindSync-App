from __future__ import annotations

import json
import os
import sys

# Allow running this script standalone while still reusing the Django-safe analyzer.
SCRIPT_DIR = os.path.dirname(__file__)
BACKEND_ROOT = os.path.abspath(os.pa6th.join(SCRIPT_DIR, "..", "..", ".."))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from face_detection.openface_results import analyze_openface_csv  # noqa: E402

def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print(
            json.dumps(
                {"error": "Usage: python results.py <openface_csv_path>"},
                ensure_ascii=False,
            )
        )
        return 2

    out = analyze_openface_csv(argv[1].strip())
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

    