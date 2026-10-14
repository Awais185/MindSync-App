from django.apps import AppConfig


class TrackingConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'tracking'
    verbose_name = 'Screen & video tracking'

    def ready(self) -> None:
        from .background_scheduler import start_background_workers

        start_background_workers()
