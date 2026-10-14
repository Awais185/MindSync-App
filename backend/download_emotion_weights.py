#!/usr/bin/env python3
"""Download facial emotion model weights into face_detection/weights/facial_emotions/."""
from pathlib import Path

from huggingface_hub import snapshot_download

REPO_ID = "dima806/facial_emotions_image_detection"
HERE = Path(__file__).resolve().parent
TARGET = HERE / "face_detection" / "weights" / "facial_emotions"


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {REPO_ID} -> {TARGET} ...")
    snapshot_download(repo_id=REPO_ID, local_dir=str(TARGET))
    print("Done.")


if __name__ == "__main__":
    main()
