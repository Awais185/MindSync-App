"""Chat app — messages and rule-based supportive replies (no generative LLM)."""

from django.apps import AppConfig


class ChatConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "chat"
    label = "chat"

    def ready(self) -> None:
        import chat.signals  # noqa: F401
