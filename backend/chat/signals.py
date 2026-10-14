from django.contrib.auth.models import User
from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import UserMentalState


@receiver(post_save, sender=User)
def ensure_user_mental_state(sender, instance: User, **kwargs):
    """Ensure a mental-state row exists (new users and legacy accounts without one)."""
    UserMentalState.objects.get_or_create(user=instance)
