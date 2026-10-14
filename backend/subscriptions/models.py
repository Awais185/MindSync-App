from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone


class SubscriptionPlan(models.Model):
    BILLING_MONTHLY = 'monthly'
    BILLING_CHOICES = ((BILLING_MONTHLY, 'Monthly'),)

    id = models.BigAutoField(primary_key=True)
    name = models.CharField(max_length=60, unique=True)
    code = models.SlugField(max_length=40, unique=True)
    price_usd = models.DecimalField(max_digits=8, decimal_places=2)
    duration_days = models.PositiveIntegerField(
        default=30,
        help_text='Subscription length after payment approval.',
    )
    billing_cycle = models.CharField(
        max_length=20,
        choices=BILLING_CHOICES,
        default=BILLING_MONTHLY,
    )
    features = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['price_usd', 'id']

    def __str__(self) -> str:
        return f'{self.name} (${self.price_usd}/{self.billing_cycle})'


class UserSubscription(models.Model):
    STATUS_ACTIVE = 'active'
    STATUS_EXPIRED = 'expired'
    STATUS_CANCELLED = 'cancelled'
    STATUS_PENDING = 'pending'
    STATUS_CHOICES = (
        (STATUS_ACTIVE, 'Active'),
        (STATUS_EXPIRED, 'Expired'),
        (STATUS_CANCELLED, 'Cancelled'),
        (STATUS_PENDING, 'Pending'),
    )

    PAYMENT_PENDING = 'pending'
    PAYMENT_PAID = 'paid'
    PAYMENT_FAILED = 'failed'
    PAYMENT_REFUNDED = 'refunded'
    PAYMENT_STATUS_CHOICES = (
        (PAYMENT_PENDING, 'Pending'),
        (PAYMENT_PAID, 'Paid'),
        (PAYMENT_FAILED, 'Failed'),
        (PAYMENT_REFUNDED, 'Refunded'),
    )

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='subscriptions',
    )
    plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.PROTECT,
        related_name='user_subscriptions',
    )
    start_date = models.DateTimeField(default=timezone.now)
    end_date = models.DateTimeField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    payment_status = models.CharField(
        max_length=20,
        choices=PAYMENT_STATUS_CHOICES,
        default=PAYMENT_PENDING,
    )
    auto_renew = models.BooleanField(default=False)
    stripe_customer_id = models.CharField(max_length=100, blank=True, default='')
    stripe_payment_intent_id = models.CharField(max_length=100, blank=True, default='')
    stripe_subscription_id = models.CharField(max_length=100, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['end_date']),
        ]

    def __str__(self) -> str:
        return f'{self.user.username} - {self.plan.name} ({self.status})'

    @staticmethod
    def default_end_date(start: timezone.datetime | None = None, *, days: int = 30) -> timezone.datetime:
        base = start or timezone.now()
        return base + timedelta(days=max(1, int(days)))

    @property
    def is_current(self) -> bool:
        now = timezone.now()
        return (
            self.status == self.STATUS_ACTIVE
            and self.payment_status == self.PAYMENT_PAID
            and self.end_date >= now
        )

    @property
    def is_active(self) -> bool:
        return self.is_current


class Payment(models.Model):
    """Manual / bank-transfer payment requests (admin approval)."""

    STATUS_PENDING = 'pending'
    STATUS_APPROVED = 'approved'
    STATUS_REJECTED = 'rejected'
    STATUS_CHOICES = (
        (STATUS_PENDING, 'Pending'),
        (STATUS_APPROVED, 'Approved'),
        (STATUS_REJECTED, 'Rejected'),
    )

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='manual_payments')
    plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.PROTECT,
        related_name='manual_payments',
    )
    subscription = models.ForeignKey(
        UserSubscription,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='manual_payments',
    )
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    payment_method = models.CharField(max_length=40, default='bank_transfer')
    transaction_reference = models.CharField(max_length=120, blank=True, default='')
    screenshot_proof = models.ImageField(
        upload_to='payments/proofs/%Y/%m/',
        blank=True,
        null=True,
    )
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_payments',
    )
    admin_note = models.CharField(max_length=500, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['status', 'created_at']),
        ]

    def __str__(self) -> str:
        return f'Payment#{self.id} {self.user_id} {self.plan.code} ({self.status})'


class Transaction(models.Model):
    PAYMENT_PENDING = 'pending'
    PAYMENT_SUCCEEDED = 'succeeded'
    PAYMENT_FAILED = 'failed'
    PAYMENT_CANCELLED = 'cancelled'
    PAYMENT_STATUS_CHOICES = (
        (PAYMENT_PENDING, 'Pending'),
        (PAYMENT_SUCCEEDED, 'Succeeded'),
        (PAYMENT_FAILED, 'Failed'),
        (PAYMENT_CANCELLED, 'Cancelled'),
    )

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='subscription_transactions')
    subscription = models.ForeignKey(
        UserSubscription,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='transactions',
    )
    subscription_plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.PROTECT,
        related_name='transactions',
    )
    manual_payment = models.ForeignKey(
        Payment,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='transactions',
    )
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=10, default='usd')
    payment_method = models.CharField(max_length=40, blank=True, default='')
    transaction_id = models.CharField(max_length=120, db_index=True)
    payment_status = models.CharField(
        max_length=20,
        choices=PAYMENT_STATUS_CHOICES,
        default=PAYMENT_PENDING,
    )
    coupon_code = models.CharField(max_length=40, blank=True, default='')
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['user', 'created_at'])]

    def __str__(self) -> str:
        return f'{self.user.username} - {self.transaction_id} - {self.payment_status}'
