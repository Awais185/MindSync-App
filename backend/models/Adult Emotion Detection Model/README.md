# Adult Emotion Detection Model

## Weights (present in this folder)

| Architecture | Files |
|--------------|--------|
| ResNet18 | `best_resnet18_fold0.pt` … `fold4.pt` |
| EfficientNet-B0 | `best_efficientnet_b0_fold0.pt` … `fold4.pt` |
| MobileNetV3-Large | `best_mobilenetv3_large_fold0.pt` … `fold4.pt` |

## Inference

MindSync loads **all three** architectures. For each:

1. Run every available fold checkpoint.
2. Average softmax probabilities across folds.

Final mood label: **average** of the three architecture probability vectors (soft vote).  
API responses also include `architecture_votes` (hard top-class per model).

Configure via `emotion_config.json` and `ADULT_EMOTION_MODEL_DIR` in Django settings.
