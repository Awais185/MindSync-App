"""Bank transfer / manual payment flow (no Stripe)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from .models import Payment, SubscriptionPlan, Transaction, UserSubscription
from .services import PaymentService, SubscriptionService


def bank_details_payload() -> dict:
    raw = getattr(settings, 'MANUAL_PAYMENT_BANK_DETAILS', None) or {}
    if isinstance(raw, dict) and raw:
        return raw
    return {
        'bank_name': 'MindSync Partner Bank',
        'account_title': 'MindSync Wellness Pvt Ltd',
        'account_number': '0000-0000-0000',
        'iban': '',
        'swift': '',
        'instructions': (
            'Transfer the exact plan amount, then submit your transaction reference '
            'and payment screenshot in the app.'
        ),
    }


class ManualPaymentService:
    @classmethod
    def create_payment_request(
        cls,
        *,
        user: User,
        plan: SubscriptionPlan,
        payment_method: str = 'bank_transfer',
        transaction_reference: str = '',
    ) -> Payment:
        amount = PaymentService._compute_amount(plan, '')
        pending = SubscriptionService.create_or_refresh_pending_subscription(
            user=user,
            plan=plan,
            auto_renew=False,
        )
        ref = (transaction_reference or '').strip()
        with transaction.atomic():
            payment = Payment.objects.create(
                user=user,
                plan=plan,
                subscription=pending,
                amount=amount,
                payment_method=(payment_method or 'bank_transfer').strip()[:40],
                transaction_reference=ref,
                status=Payment.STATUS_PENDING,
            )
            tx_id = f'manual-{payment.id}-{uuid.uuid4().hex[:8]}'
            PaymentService.create_transaction(
                user=user,
                subscription=pending,
                plan=plan,
                payment_intent_id=tx_id,
                payment_method=payment.payment_method,
                amount=amount,
                payment_status=Transaction.PAYMENT_PENDING,
                metadata={'gateway': 'manual', 'payment_id': payment.id},
                manual_payment=payment,
            )
        return payment

    @classmethod
    def attach_proof(
        cls,
        *,
        payment: Payment,
        screenshot,
        transaction_reference: str = '',
    ) -> Payment:
        if screenshot is not None:
            payment.screenshot_proof = screenshot
        ref = (transaction_reference or '').strip()
        if ref:
            payment.transaction_reference = ref
        payment.save(update_fields=['screenshot_proof', 'transaction_reference', 'updated_at'])
        return payment

    @classmethod
    def approve(cls, *, payment: Payment, reviewer: User) -> UserSubscription:
        if payment.status != Payment.STATUS_PENDING:
            raise ValueError(f'Payment is already {payment.status}.')
        if not payment.subscription_id:
            raise ValueError('Payment has no linked subscription.')

        sub = payment.subscription
        plan = payment.plan
        days = max(1, int(getattr(plan, 'duration_days', None) or 30))
        tx_id = f'manual-approved-{payment.id}'

        with transaction.atomic():
            now = timezone.now()
            UserSubscription.objects.filter(
                user=payment.user,
                status=UserSubscription.STATUS_ACTIVE,
            ).exclude(id=sub.id).update(
                status=UserSubscription.STATUS_CANCELLED,
                auto_renew=False,
            )
            sub.plan = plan
            sub.status = UserSubscription.STATUS_ACTIVE
            sub.payment_status = UserSubscription.PAYMENT_PAID
            sub.start_date = now
            sub.end_date = now + timedelta(days=days)
            sub.stripe_payment_intent_id = tx_id
            sub.auto_renew = False
            sub.save()

            payment.status = Payment.STATUS_APPROVED
            payment.reviewed_at = now
            payment.reviewed_by = reviewer
            payment.save(update_fields=['status', 'reviewed_at', 'reviewed_by', 'updated_at'])

            Transaction.objects.filter(manual_payment=payment).update(
                payment_status=Transaction.PAYMENT_SUCCEEDED,
                transaction_id=tx_id,
            )

        return sub

    @classmethod
    def reject(cls, *, payment: Payment, reviewer: User, note: str = '') -> Payment:
        if payment.status != Payment.STATUS_PENDING:
            raise ValueError(f'Payment is already {payment.status}.')

        with transaction.atomic():
            payment.status = Payment.STATUS_REJECTED
            payment.reviewed_at = timezone.now()
            payment.reviewed_by = reviewer
            payment.admin_note = (note or '')[:500]
            payment.save(
                update_fields=['status', 'reviewed_at', 'reviewed_by', 'admin_note', 'updated_at']
            )
            if payment.subscription_id:
                sub = payment.subscription
                sub.status = UserSubscription.STATUS_CANCELLED
                sub.payment_status = UserSubscription.PAYMENT_FAILED
                sub.auto_renew = False
                sub.save(update_fields=['status', 'payment_status', 'auto_renew', 'updated_at'])
            Transaction.objects.filter(manual_payment=payment).update(
                payment_status=Transaction.PAYMENT_FAILED,
            )
        return payment
