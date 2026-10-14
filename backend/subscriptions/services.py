from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal
import logging
import os

from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from .constants import PLAN_BASIC, PLAN_FREE, PLAN_PREMIUM
from .models import SubscriptionPlan, Transaction, UserSubscription

logger = logging.getLogger(__name__)


@dataclass
class PaymentCreationResult:
    client_secret: str
    payment_intent_id: str
    amount: Decimal
    currency: str
    order_summary: dict


class SubscriptionService:
    FEATURE_BY_PLAN = {
        PLAN_FREE: {
            'basic_mood_tracking',
            'screen_time',
        },
        PLAN_BASIC: {
            'emotion_detection_limited',
            'basic_mood_tracking',
            'screen_time',
            'content_monitoring',
            'chat_realtime_psychologist',
            'analytics_day_week_month',
            'ads_included',
        },
        PLAN_PREMIUM: {
            'emotion_detection_limited',
            'emotion_detection_full',
            'basic_mood_tracking',
            'screen_time',
            'content_monitoring',
            'chat_realtime_psychologist',
            'analytics_day_week_month',
            'ads_included',
            'weekly_reports',
            'no_ads',
            'personalized_suggestions',
            'chat_digital_psychologist',
            'mental_health_monitoring',
            'advanced_ai_insights',
            'monthly_mental_health_reports',
            'therapist_recommendation',
            'priority_support',
            'parental_control',
            'full_app_access',
        },
    }

    @classmethod
    def get_active_subscription(cls, user: User) -> UserSubscription | None:
        cls.expire_user_subscriptions(user)
        now = timezone.now()
        return (
            UserSubscription.objects.filter(
                user=user,
                status=UserSubscription.STATUS_ACTIVE,
                payment_status=UserSubscription.PAYMENT_PAID,
                end_date__gte=now,
                plan__is_active=True,
            )
            .select_related('plan')
            .order_by('-end_date')
            .first()
        )

    @classmethod
    def current_plan_code(cls, user: User) -> str:
        current = cls.get_active_subscription(user)
        if not current:
            return PLAN_FREE
        return (current.plan.code or PLAN_FREE).lower()

    @classmethod
    def can_access_feature(cls, user: User, feature_key: str) -> bool:
        plan_code = cls.current_plan_code(user)
        allowed = cls.FEATURE_BY_PLAN.get(plan_code, cls.FEATURE_BY_PLAN[PLAN_FREE])
        return feature_key in allowed

    @classmethod
    def create_or_refresh_pending_subscription(
        cls,
        *,
        user: User,
        plan: SubscriptionPlan,
        auto_renew: bool,
    ) -> UserSubscription:
        now = timezone.now()
        pending = UserSubscription.objects.filter(
            user=user,
            status=UserSubscription.STATUS_PENDING,
            payment_status=UserSubscription.PAYMENT_PENDING,
        ).order_by('-created_at').first()

        days = max(1, int(getattr(plan, 'duration_days', None) or 30))
        end_date = now + timedelta(days=days)
        if pending:
            pending.plan = plan
            pending.start_date = now
            pending.end_date = end_date
            pending.auto_renew = auto_renew
            pending.save(
                update_fields=[
                    'plan',
                    'start_date',
                    'end_date',
                    'auto_renew',
                    'updated_at',
                ]
            )
            return pending

        return UserSubscription.objects.create(
            user=user,
            plan=plan,
            start_date=now,
            end_date=end_date,
            status=UserSubscription.STATUS_PENDING,
            payment_status=UserSubscription.PAYMENT_PENDING,
            auto_renew=auto_renew,
        )

    @classmethod
    def activate_subscription_after_payment(
        cls,
        *,
        user: User,
        subscription: UserSubscription,
        payment_intent_id: str,
    ) -> UserSubscription:
        with transaction.atomic():
            now = timezone.now()
            UserSubscription.objects.filter(
                user=user,
                status=UserSubscription.STATUS_ACTIVE,
            ).exclude(id=subscription.id).update(
                status=UserSubscription.STATUS_CANCELLED,
                auto_renew=False,
            )
            subscription.status = UserSubscription.STATUS_ACTIVE
            subscription.payment_status = UserSubscription.PAYMENT_PAID
            subscription.start_date = now
            days = max(1, int(getattr(subscription.plan, 'duration_days', None) or 30))
            subscription.end_date = now + timedelta(days=days)
            subscription.stripe_payment_intent_id = payment_intent_id
            subscription.save()
        return subscription

    @classmethod
    def cancel_subscription(cls, *, subscription: UserSubscription, immediate: bool) -> UserSubscription:
        if immediate:
            subscription.status = UserSubscription.STATUS_CANCELLED
            subscription.end_date = timezone.now()
        subscription.auto_renew = False
        subscription.save(update_fields=['status', 'end_date', 'auto_renew', 'updated_at'])
        return subscription

    @classmethod
    def expire_user_subscriptions(cls, user: User) -> int:
        now = timezone.now()
        updated = UserSubscription.objects.filter(
            user=user,
            status=UserSubscription.STATUS_ACTIVE,
            end_date__lt=now,
        ).update(status=UserSubscription.STATUS_EXPIRED, auto_renew=False)
        return updated

    @classmethod
    def expire_all_subscriptions(cls) -> int:
        now = timezone.now()
        updated = UserSubscription.objects.filter(
            status=UserSubscription.STATUS_ACTIVE,
            end_date__lt=now,
        ).update(status=UserSubscription.STATUS_EXPIRED, auto_renew=False)
        return updated


class PaymentService:
    @staticmethod
    def _stripe():
        import stripe

        stripe.api_key = (os.environ.get('STRIPE_SECRET_KEY') or '').strip()
        if not stripe.api_key:
            raise RuntimeError('Stripe is not configured. Set STRIPE_SECRET_KEY.')
        return stripe

    @classmethod
    def _compute_amount(cls, plan: SubscriptionPlan, coupon_code: str) -> Decimal:
        amount = Decimal(plan.price_usd)
        coupon = (coupon_code or '').strip().upper()
        if coupon == 'MINDSYNC10':
            amount = amount * Decimal('0.90')
        elif coupon == 'MINDSYNC20':
            amount = amount * Decimal('0.80')
        return amount.quantize(Decimal('0.01'))

    @classmethod
    def create_payment_intent(
        cls,
        *,
        user: User,
        plan: SubscriptionPlan,
        payment_method: str,
        coupon_code: str,
    ) -> PaymentCreationResult:
        stripe = cls._stripe()
        amount = cls._compute_amount(plan, coupon_code)
        amount_cents = int(amount * 100)

        intent = stripe.PaymentIntent.create(
            amount=amount_cents,
            currency='usd',
            payment_method_types=['card'],
            metadata={
                'user_id': str(user.id),
                'plan_id': str(plan.id),
                'plan_code': plan.code,
                'coupon': coupon_code or '',
                'payment_method': payment_method or 'card',
            },
        )

        return PaymentCreationResult(
            client_secret=intent.client_secret,
            payment_intent_id=intent.id,
            amount=amount,
            currency='usd',
            order_summary={
                'plan': plan.name,
                'billing_cycle': plan.billing_cycle,
                'base_price_usd': str(plan.price_usd),
                'final_price_usd': str(amount),
                'coupon_code': coupon_code or '',
                'payment_methods_supported': ['card', 'wallet'],
            },
        )

    @classmethod
    def verify_payment_intent(cls, payment_intent_id: str) -> dict:
        stripe = cls._stripe()
        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        return {
            'id': intent.id,
            'status': intent.status,
            'payment_method': intent.payment_method_types[0] if intent.payment_method_types else 'card',
            'amount': Decimal(intent.amount) / Decimal(100),
            'currency': intent.currency,
            'metadata': intent.metadata or {},
        }

    @classmethod
    def create_transaction(
        cls,
        *,
        user: User,
        subscription: UserSubscription,
        plan: SubscriptionPlan,
        payment_intent_id: str,
        payment_method: str,
        amount: Decimal,
        payment_status: str,
        coupon_code: str = '',
        metadata: dict | None = None,
        manual_payment=None,
    ) -> Transaction:
        return Transaction.objects.create(
            user=user,
            subscription=subscription,
            subscription_plan=plan,
            manual_payment=manual_payment,
            amount=amount,
            currency='usd',
            payment_method=payment_method or 'card',
            transaction_id=payment_intent_id,
            payment_status=payment_status,
            coupon_code=coupon_code or '',
            metadata=metadata or {},
        )
