from django.apps import AppConfig


class FaceDetectionConfig(AppConfig):
    name = 'face_detection'

    def ready(self) -> None:
        import face_detection.signals  # noqa: F401
        
        import threading
        import logging
        logger = logging.getLogger(__name__)
        
        def preload_model():
            try:
                from face_detection.emotion_models import get_classifier
                get_classifier()
                logger.info("Emotion classifier pre-loaded successfully during startup.")
            except Exception as e:
                logger.warning("Failed to preload emotion classifier: %s", e)
                
        threading.Thread(target=preload_model, daemon=True).start()
