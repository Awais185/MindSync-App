# Chat app ML weights (`chat/weights/`)

Place artifacts here for **fast local loading** (no re-download each server start).

## Recommended (Hugging Face emotion model)

1. From `MindSync/backend` run:
   ```bash
   python download_chat_weights.py
   ```
2. This fills `chat/weights/hf_emotion/` with `dima806/facial_emotions_image_detection`.

## Optional TorchScript checkpoints

- **`image_model.pth`** — TorchScript module; input: N×3×224×224 ImageNet-normalized RGB (see `chat/models.py` transforms). Optional **`image_labels.json`**: `["happy", "sad", ...]` in class index order.
- **`video_model.pth`** — Used for **video** analysis when present; otherwise the same backend as image (HF or `image_model.pth`) is applied per frame.

If neither `.pth` nor `hf_emotion/` exists, the hub model id from settings is used (cached under `~/.cache/huggingface`).
