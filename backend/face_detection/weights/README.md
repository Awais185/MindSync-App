# Emotion model weights (local)

To download `dima806/facial_emotions_image_detection` into this folder for faster startup (no re-download from the Hub on each server run):

```bash
cd MindSync/backend
python download_emotion_weights.py
```

The script writes into `face_detection/weights/facial_emotions/`. If this folder is empty or missing model files, the API falls back to loading the model id from Hugging Face (cached in `~/.cache/huggingface`).
