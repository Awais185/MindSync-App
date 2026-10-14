---
license: apache-2.0
metrics:
- accuracy
- f1
base_model:
- google/vit-base-patch16-224-in21k
---
Returns facial emotion with about 91% accuracy based on facial human image.

See https://www.kaggle.com/code/dima806/facial-emotions-image-detection-vit for more details.

![image/png](https://cdn-uploads.huggingface.co/production/uploads/6449300e3adf50d864095b90/dr6xp-8bjXk0TqXfJaBDn.png)

```
Classification report:

              precision    recall  f1-score   support

         sad     0.8394    0.8632    0.8511      3596
     disgust     0.9909    1.0000    0.9954      3596
       angry     0.9022    0.9035    0.9028      3595
     neutral     0.8752    0.8626    0.8689      3595
        fear     0.8788    0.8532    0.8658      3596
    surprise     0.9476    0.9449    0.9463      3596
       happy     0.9302    0.9372    0.9336      3596

    accuracy                         0.9092     25170
   macro avg     0.9092    0.9092    0.9091     25170
weighted avg     0.9092    0.9092    0.9091     25170
```