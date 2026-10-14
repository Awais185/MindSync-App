from django.urls import path

from .payment_views import (
    AdminApprovePaymentAPIView,
    AdminPaymentListAPIView,
    AdminRejectPaymentAPIView,
    BankDetailsAPIView,
    CreateManualPaymentAPIView,
    CurrentSubscriptionAliasAPIView,
    UploadPaymentProofAPIView,
)
from .views import (
    AdminAssignSubscriptionAPIView,
    CancelSubscriptionAPIView,
    ConfirmSubscriptionPaymentAPIView,
    CreatePaymentAPIView,
    CurrentSubscriptionAPIView,
    PaymentHistoryAPIView,
    PaymentWebhookAPIView,
    PlansAPIView,
    SubscribeAPIView,
    UpgradeAPIView,
)

urlpatterns = [
    path('plans/', PlansAPIView.as_view(), name='plans'),
    path('subscribe/', SubscribeAPIView.as_view(), name='subscribe'),
    path('upgrade/', UpgradeAPIView.as_view(), name='upgrade'),
    path('create-payment/', CreatePaymentAPIView.as_view(), name='create_payment'),
    path('payment/webhook/', PaymentWebhookAPIView.as_view(), name='payment_webhook'),
    path('cancel-subscription/', CancelSubscriptionAPIView.as_view(), name='cancel_subscription'),
    path('current-subscription/', CurrentSubscriptionAPIView.as_view(), name='current_subscription'),
    path('payment-history/', PaymentHistoryAPIView.as_view(), name='payment_history'),
    path('confirm-payment/', ConfirmSubscriptionPaymentAPIView.as_view(), name='confirm_subscription_payment'),
    path('admin/assign-subscription/', AdminAssignSubscriptionAPIView.as_view(), name='admin_assign_subscription'),
    # Manual / bank payments
    path('payments/bank-details/', BankDetailsAPIView.as_view(), name='payments_bank_details'),
    path('payments/create/', CreateManualPaymentAPIView.as_view(), name='payments_create'),
    path('payments/upload-proof/', UploadPaymentProofAPIView.as_view(), name='payments_upload_proof'),
    path('subscription/current/', CurrentSubscriptionAliasAPIView.as_view(), name='subscription_current'),
    path('admin/payments/', AdminPaymentListAPIView.as_view(), name='admin_payments_list'),
    path('admin/payment/approve/<int:pk>/', AdminApprovePaymentAPIView.as_view(), name='admin_payment_approve'),
    path('admin/payment/reject/<int:pk>/', AdminRejectPaymentAPIView.as_view(), name='admin_payment_reject'),
]
