import os
import sys

# Add backend dir to pythonpath
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
import django
django.setup()

import urllib.request
from face_detection.face_verification_service import compute_embedding, cosine_distance

def download_image(url):
    # Spoof user-agent to bypass wiki restrictions
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    return urllib.request.urlopen(req).read()

print("Downloading test images...")
try:
    obama1_url = "https://upload.wikimedia.org/wikipedia/commons/8/8d/President_Barack_Obama.jpg"
    obama1_bytes = download_image(obama1_url)

    obama2_url = "https://upload.wikimedia.org/wikipedia/commons/e/e9/Official_portrait_of_Barack_Obama.jpg"
    obama2_bytes = download_image(obama2_url)

    biden_url = "https://upload.wikimedia.org/wikipedia/commons/6/68/Joe_Biden_presidential_portrait.jpg"
    biden_bytes = download_image(biden_url)

    empty_bytes = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\n\x00\x00\x00\n\x08\x02\x00\x00\x00\x02PX\xea\x00\x00\x00\x16IDATx\x9cc\xfc\xff\xff?\x03\t\x04\x02\x18\x00\x00\x08\xd0\x01\x14\x95\x9e\xbc\x0e\x00\x00\x00\x00IEND\xaeB`\x82'

    print("Extracting embeddings...")
    emb_obama1 = compute_embedding(obama1_bytes)
    emb_obama2 = compute_embedding(obama2_bytes)
    emb_biden = compute_embedding(biden_bytes)
    emb_empty = compute_embedding(empty_bytes)

    print(f"Obama 1 embedding extracted: {emb_obama1 is not None}")
    print(f"Obama 2 embedding extracted: {emb_obama2 is not None}")
    print(f"Biden embedding extracted: {emb_biden is not None}")
    print(f"Empty embedding extracted: {emb_empty is not None}")

    if emb_obama1 is not None and emb_obama2 is not None:
        dist_same = cosine_distance(emb_obama1, emb_obama2)
        print(f"Distance (Obama1 vs Obama2): {dist_same:.4f} (Expect < 0.5)")

    if emb_obama1 is not None and emb_biden is not None:
        dist_diff = cosine_distance(emb_obama1, emb_biden)
        print(f"Distance (Obama1 vs Biden): {dist_diff:.4f} (Expect > 0.5)")
except Exception as e:
    print(f"Error during testing: {e}")
