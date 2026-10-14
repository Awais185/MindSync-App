from __future__ import annotations

from django.conf import settings
from django.http import HttpResponse
from django.utils import timezone
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from rest_framework import permissions, response, status
from rest_framework.views import APIView

from subscriptions.models import SubscriptionPlan, Transaction, UserSubscription
from subscriptions.services import PaymentService, SubscriptionService

from .plans import get_plan_by_code, list_public_plans
from .serializers import (
    ConfirmSubscriptionSerializer,
    CreatePaymentIntentSerializer,
    PaymentHistorySerializer,
    subscription_payload_from_user_sub,
)


def _publishable_key() -> str:
    return (getattr(settings, 'STRIPE_PUBLISHABLE_KEY', '') or '').strip()


class CreatePaymentIntentView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = CreatePaymentIntentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        plan_row = get_plan_by_code(serializer.validated_data['plan_id'])
        if not plan_row:
            return response.Response(
                {'error': 'Invalid plan_id. Use basic or premium.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        plan = SubscriptionPlan.objects.filter(id=plan_row['plan_db_id'], is_active=True).first()
        if not plan:
            return response.Response({'error': 'Plan not available.'}, status=status.HTTP_404_NOT_FOUND)

        current = SubscriptionService.get_active_subscription(request.user)
        if current and current.plan_id == plan.id:
            return response.Response(
                {'error': 'You are already subscribed to this plan.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            pending = SubscriptionService.create_or_refresh_pending_subscription(
                user=request.user,
                plan=plan,
                auto_renew=True,
            )
            payment = PaymentService.create_payment_intent(
                user=request.user,
                plan=plan,
                payment_method='card',
                coupon_code='',
            )
            pending.stripe_payment_intent_id = payment.payment_intent_id
            pending.save(update_fields=['stripe_payment_intent_id', 'updated_at'])

            PaymentService.create_transaction(
                user=request.user,
                subscription=pending,
                plan=plan,
                payment_intent_id=payment.payment_intent_id,
                payment_method='card',
                amount=payment.amount,
                payment_status=Transaction.PAYMENT_PENDING,
                metadata={'api': 'payments/create-payment-intent'},
            )
        except Exception as exc:
            return response.Response(
                {'error': f'Could not initiate payment: {exc}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        public_plan = {k: v for k, v in plan_row.items() if k != 'plan_db_id'}
        return response.Response(
            {
                'client_secret': payment.client_secret,
                'publishable_key': _publishable_key(),
                'payment_intent_id': payment.payment_intent_id,
                'plan': public_plan,
            },
            status=status.HTTP_201_CREATED,
        )


class ConfirmSubscriptionView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = ConfirmSubscriptionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payment_intent_id = serializer.validated_data['payment_intent_id']
        plan_row = get_plan_by_code(serializer.validated_data['plan_id'])
        if not plan_row:
            return response.Response({'error': 'Invalid plan_id.'}, status=status.HTTP_400_BAD_REQUEST)

        pending = UserSubscription.objects.filter(
            user=request.user,
            stripe_payment_intent_id=payment_intent_id,
            status=UserSubscription.STATUS_PENDING,
        ).select_related('plan').first()
        if not pending:
            return response.Response(
                {'error': 'Pending subscription not found for this payment intent.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            verified = PaymentService.verify_payment_intent(payment_intent_id)
        except Exception as exc:
            return response.Response(
                {'error': f'Payment verification failed: {exc}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        stripe_status = str(verified.get('status', '')).lower()
        if stripe_status != 'succeeded':
            return response.Response(
                {
                    'error': 'Payment not completed',
                    'stripe_status': stripe_status,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        sub = SubscriptionService.activate_subscription_after_payment(
            user=request.user,
            subscription=pending,
            payment_intent_id=payment_intent_id,
        )
        tx = Transaction.objects.filter(
            user=request.user,
            transaction_id=payment_intent_id,
        ).order_by('-created_at').first()
        if tx:
            tx.payment_status = Transaction.PAYMENT_SUCCEEDED
            tx.amount = verified.get('amount') or tx.amount
            tx.save(update_fields=['payment_status', 'amount'])

        return response.Response(
            {
                'success': True,
                'subscription': subscription_payload_from_user_sub(sub),
            }
        )


class MySubscriptionView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        SubscriptionService.expire_user_subscriptions(request.user)
        current = SubscriptionService.get_active_subscription(request.user)
        if current:
            return response.Response({'subscription': subscription_payload_from_user_sub(current)})

        latest = (
            UserSubscription.objects.filter(user=request.user)
            .select_related('plan')
            .order_by('-created_at')
            .first()
        )
        if latest and latest.status == UserSubscription.STATUS_ACTIVE and latest.end_date < timezone.now():
            latest.status = UserSubscription.STATUS_EXPIRED
            latest.save(update_fields=['status', 'updated_at'])

        if latest and latest.payment_status == UserSubscription.PAYMENT_PAID:
            return response.Response({'subscription': subscription_payload_from_user_sub(latest)})
        return response.Response({'subscription': None})


class PaymentHistoryView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        rows = Transaction.objects.filter(user=request.user).select_related('subscription_plan')
        return response.Response({'results': PaymentHistorySerializer(rows, many=True).data})


@method_decorator(csrf_exempt, name='dispatch')
class StripeWebhookView(APIView):
    permission_classes = (permissions.AllowAny,)
    authentication_classes = ()

    def post(self, request):
        signature = request.headers.get('Stripe-Signature', '')
        webhook_secret = (getattr(settings, 'STRIPE_WEBHOOK_SECRET', '') or '').strip()
        payload = request.body

        if signature and webhook_secret:
            try:
                stripe = PaymentService._stripe()
                event = stripe.Webhook.construct_event(
                    payload=payload,
                    sig_header=signature,
                    secret=webhook_secret,
                )
            except Exception:
                return HttpResponse(status=400)
            event_type = str(event.get('type') or '').lower()
            obj = (event.get('data') or {}).get('object') or {}
            payment_intent_id = str(obj.get('id') or '').strip()
        else:
            import json

            try:
                data = json.loads(payload.decode() or '{}')
            except Exception:
                data = {}
            event_type = str(data.get('type') or '').lower()
            obj = (data.get('data') or {}).get('object') or data.get('object') or {}
            payment_intent_id = str(
                data.get('payment_intent_id') or obj.get('id') or ''
            ).strip()

        if not payment_intent_id:
            return HttpResponse(status=200)

        pending = UserSubscription.objects.filter(
            stripe_payment_intent_id=payment_intent_id,
        ).select_related('user', 'plan').first()

        if event_type == 'payment_intent.succeeded' and pending:
            if pending.status == UserSubscription.STATUS_PENDING:
                SubscriptionService.activate_subscription_after_payment(
                    user=pending.user,
                    subscription=pending,
                    payment_intent_id=payment_intent_id,
                )
            Transaction.objects.filter(transaction_id=payment_intent_id).update(
                payment_status=Transaction.PAYMENT_SUCCEEDED
            )
        elif event_type == 'payment_intent.payment_failed' and pending:
            pending.payment_status = UserSubscription.PAYMENT_FAILED
            pending.status = UserSubscription.STATUS_CANCELLED
            pending.auto_renew = False
            pending.save(update_fields=['payment_status', 'status', 'auto_renew', 'updated_at'])
            Transaction.objects.filter(transaction_id=payment_intent_id).update(
                payment_status=Transaction.PAYMENT_FAILED
            )

        return HttpResponse(status=200)


class PlansListView(APIView):
    permission_classes = (permissions.AllowAny,)
    authentication_classes = ()

    def get(self, request):
        plans = [{k: v for k, v in p.items() if k != 'plan_db_id'} for p in list_public_plans()]
        return response.Response({'plans': plans})
