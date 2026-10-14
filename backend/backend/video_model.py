import os
import torch
from transformers import VideoLlavaForConditionalGeneration, VideoLlavaProcessor

# 🔥 CHANGE THIS PATH (Google Drive recommended)
SAVE_PATH = "/content/drive/MyDrive/video_llava_model"

os.makedirs(SAVE_PATH, exist_ok=True)

device = "cuda" if torch.cuda.is_available() else "cpu"

MODEL_NAME = "LanguageBind/Video-LLaVA-7B-hf"

print("Loading model...")

model = VideoLlavaForConditionalGeneration.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16 if device == "cuda" else torch.float32,
    device_map="auto"
)

processor = VideoLlavaProcessor.from_pretrained(MODEL_NAME)

print("Saving model...")

# ✅ Correct way (important)
model.save_pretrained(SAVE_PATH)
processor.save_pretrained(SAVE_PATH)

print(f"✅ Model saved successfully at: {SAVE_PATH}")



import os
import torch
from transformers import VideoLlavaForConditionalGeneration, VideoLlavaProcessor

# 🔥 CHANGE THIS PATH (Google Drive recommended)
SAVE_PATH = "D:\\c drive data\\MindSync (1)\\MindSync\\backend\\backend\\saved_Video_model"

os.makedirs(SAVE_PATH, exist_ok=True)

device = "cuda" if torch.cuda.is_available() else "cpu"

MODEL_NAME = "LanguageBind/Video-LLaVA-7B-hf"

print("Loading model...")

model = VideoLlavaForConditionalGeneration.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16 if device == "cuda" else torch.float32,
    device_map="auto"
)

processor = VideoLlavaProcessor.from_pretrained(MODEL_NAME)

print("Saving model...")

# ✅ Correct way (important)
model.save_pretrained(SAVE_PATH)
processor.save_pretrained(SAVE_PATH)

print(f"✅ Model saved successfully at: {SAVE_PATH}")