from django.apps import AppConfig


class FaceDetectionConfig(AppConfig):
    name = 'face_detection'

    def ready(self) -> None:
        import os

        import face_detection.signals  # noqa: F401

        import threading
        import logging
        logger = logging.getLogger(__name__)

        if os.environ.get('MINDSYNC_SKIP_EMOTION_PRELOAD', '').strip().lower() in (
            '1',
            'true',
            'yes',
        ):
            return

        def preload_model():
            try:
                from face_detection.analysis_warmup import ensure_behavior_models_warm

                ensure_behavior_models_warm()
                logger.info("Deep Face Analysis models pre-loaded at startup.")
            except Exception as e:
                logger.warning("Failed to preload behavior analysis models: %s", e)

        threading.Thread(target=preload_model, daemon=True).start()
