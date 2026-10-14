from django.urls import path
from .views import (
    ContactSubmissionCreateView,
    NewsletterSubscribeView,
    WebsiteHealthView,
)

app_name = 'website'

urlpatterns = [
    path('contact/', ContactSubmissionCreateView.as_view(), name='contact'),
    path('newsletter/', NewsletterSubscribeView.as_view(), name='newsletter'),
    path('health/', WebsiteHealthView.as_view(), name='health'),
]