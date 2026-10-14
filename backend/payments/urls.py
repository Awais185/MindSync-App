from django.urls import path

from .views import (
    ConfirmSubscriptionView,
    CreatePaymentIntentView,
    MySubscriptionView,
    PaymentHistoryView,
    PlansListView,
    StripeWebhookView,
)

urlpatterns = [
    path('create-payment-intent/', CreatePaymentIntentView.as_view()),
    path('confirm-subscription/', ConfirmSubscriptionView.as_view()),
    path('my-subscription/', MySubscriptionView.as_view()),
    path('history/', PaymentHistoryView.as_view()),
    path('webhook/', StripeWebhookView.as_view()),
    path('plans/', PlansListView.as_view()),
]
