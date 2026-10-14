import os
import av
import torch
import numpy as np
from transformers import VideoLlavaForConditionalGeneration, VideoLlavaProcessor

# 🔥 PATHS
MODEL_PATH = "/content/drive/MyDrive/video_llava_model"
VIDEO_PATH = "/content/your_video.mp4"   # <-- CHANGE THIS

device = "cuda" if torch.cuda.is_available() else "cpu"


# -------- VIDEO READER --------
def read_video_pyav(container, num_frames=8):
    frames = []
    container.seek(0)

    for frame in container.decode(video=0):
        frames.append(frame.to_ndarray(format="rgb24"))

    if len(frames) == 0:
        raise ValueError("No frames decoded from video.")

    indices = np.linspace(0, len(frames) - 1, num_frames).astype(int)
    sampled_frames = [frames[i] for i in indices]

    return np.stack(sampled_frames)


# -------- LOAD MODEL --------
print("Loading model...")

model = VideoLlavaForConditionalGeneration.from_pretrained(
    MODEL_PATH,
    torch_dtype=torch.float16 if device == "cuda" else torch.float32
).to(device)

processor = VideoLlavaProcessor.from_pretrained(MODEL_PATH)

print("✅ Model loaded successfully!")


# -------- LOAD VIDEO --------
if not os.path.exists(VIDEO_PATH):
    raise FileNotFoundError(f"❌ Video not found: {VIDEO_PATH}")

print("Opening video...")

container = av.open(VIDEO_PATH)
video = read_video_pyav(container)


# -------- YOUR PROMPT --------
prompt = """
USER: <video>

You are an AI behavioral analyst.

Analyze the person in this video and provide a structured psychological observation.

Focus on:
1. Facial expressions (stress, sadness, anxiety, calmness)
2. Body language (restlessness, tension, stillness)
3. Eye movement and attention
4. Interaction with objects (nervous behavior, distraction)
5. Overall emotional state

Then classify:
- Stress Level: Low / Medium / High
- Anxiety Indicators: Yes / No (with explanation)
- Emotional State: (e.g., calm, stressed, anxious, frustrated)

Finally provide:
- Short explanation (2–3 lines)
- Confidence level: Low / Medium / High

Important:
- Do NOT describe the scene
- Focus only on psychological and behavioral analysis
- Be concise and structured

ASSISTANT:
"""


# -------- PREPARE INPUT --------
inputs = processor(
    text=prompt,
    videos=video,
    return_tensors="pt"
).to(device)


# -------- GENERATE OUTPUT --------
print("Analyzing video...")

output = model.generate(
    **inputs,
    max_new_tokens=150,
    do_sample=True,
    temperature=0.7
)

result = processor.batch_decode(output, skip_special_tokens=True)[0]

print("\n🧠 AI Analysis Result:\n")
print(result)