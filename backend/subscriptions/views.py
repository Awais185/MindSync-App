from __future__ import annotations

from datetime import timedelta
from django.conf import settings
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework import permissions, response, status
from rest_framework.views import APIView

from .models import SubscriptionPlan, Transaction, UserSubscription
from .serializers import (
    CreatePaymentRequestSerializer,
    AdminAssignSubscriptionSerializer,
    CancelSubscriptionRequestSerializer,
    ConfirmPaymentSerializer,
    SubscriptionPlanSerializer,
    TransactionSerializer,
    UserSubscriptionSerializer,
)
from .services import PaymentService, SubscriptionService

FREE_PLAN_PAYLOAD = {
    'id': 0,
    'name': 'Free',
    'code': 'free',
    'price_usd': '0.00',
    'billing_cycle': 'monthly',
    'features': [
        'Very limited app access',
        'Basic mood tracking',
        'Screen time tracking',
    ],
    'is_active': True,
}


class PlansAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        plans = SubscriptionPlan.objects.filter(is_active=True).order_by('price_usd')
        payload = [FREE_PLAN_PAYLOAD, *SubscriptionPlanSerializer(plans, many=True).data]
        return response.Response({'plans': payload})


class CurrentSubscriptionAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        current = SubscriptionService.get_active_subscription(request.user)
        if not current:
            return response.Response(
                {
                    'subscription': None,
                    'effective_plan_code': 'free',
                    'plan': FREE_PLAN_PAYLOAD,
                    'status': 'inactive',
                    'message': 'No active paid subscription. Free plan is applied.',
                }
            )
        return response.Response(
            {
                'subscription': UserSubscriptionSerializer(current).data,
                'effective_plan_code': current.plan.code,
                'plan': SubscriptionPlanSerializer(current.plan).data,
                'status': current.status,
            }
        )


class SubscribeAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        return response.Response(
            {
                'message': 'Deprecated endpoint. Use /api/create-payment/ with flow=subscribe.',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )


class UpgradeAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        return response.Response(
            {
                'message': 'Deprecated endpoint. Use /api/create-payment/ with flow=upgrade.',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )


class CreatePaymentAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = CreatePaymentRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        plan = SubscriptionPlan.objects.filter(id=data['plan_id'], is_active=True).first()
        if not plan:
            return response.Response({'message': 'Selected plan is not available.'}, status=status.HTTP_404_NOT_FOUND)

        flow = data.get('flow') or CreatePaymentRequestSerializer.FLOW_SUBSCRIBE
        current = SubscriptionService.get_active_subscription(request.user)
        if current and current.plan_id == plan.id:
            return response.Response({'message': 'You are already subscribed to this plan.'}, status=status.HTTP_400_BAD_REQUEST)
        if flow == CreatePaymentRequestSerializer.FLOW_UPGRADE and not current:
            return response.Response(
                {'message': 'No active plan to upgrade. Use flow=subscribe.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            pending = SubscriptionService.create_or_refresh_pending_subscription(
                user=request.user,
                plan=plan,
                auto_renew=bool(data.get('auto_renew')),
            )
            payment = PaymentService.create_payment_intent(
                user=request.user,
                plan=plan,
                payment_method=data.get('payment_method') or 'card',
                coupon_code=data.get('coupon_code') or '',
            )
            pending.stripe_payment_intent_id = payment.payment_intent_id
            pending.save(update_fields=['stripe_payment_intent_id', 'updated_at'])

            PaymentService.create_transaction(
                user=request.user,
                subscription=pending,
                plan=plan,
                payment_intent_id=payment.payment_intent_id,
                payment_method=data.get('payment_method') or 'card',
                amount=payment.amount,
                payment_status=Transaction.PAYMENT_PENDING,
                coupon_code=data.get('coupon_code') or '',
                metadata={
                    'flow': flow,
                    'gateway': (data.get('payment_gateway') or 'stripe').lower(),
                },
            )
        except Exception as exc:
            return response.Response(
                {'message': f'Could not initiate payment: {exc}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return response.Response(
            {
                'message': 'Payment order created. Complete payment to activate subscription.',
                'subscription_id': pending.id,
                'payment_intent_id': payment.payment_intent_id,
                'client_secret': payment.client_secret,
                'payment_gateway': (data.get('payment_gateway') or 'stripe').lower(),
                'order_summary': payment.order_summary,
            },
            status=status.HTTP_201_CREATED,
        )


class ConfirmSubscriptionPaymentAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = ConfirmPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payment_intent_id = serializer.validated_data['payment_intent_id']

        pending = UserSubscription.objects.filter(
            user=request.user,
            stripe_payment_intent_id=payment_intent_id,
            status=UserSubscription.STATUS_PENDING,
        ).select_related('plan').first()
        if not pending:
            return response.Response(
                {'message': 'Pending subscription not found for this payment intent.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            verified = PaymentService.verify_payment_intent(payment_intent_id)
        except Exception as exc:
            return response.Response(
                {'message': f'Payment verification failed: {exc}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tx = Transaction.objects.filter(
            user=request.user,
            subscription=pending,
            transaction_id=payment_intent_id,
        ).order_by('-created_at').first()

        payment_status = str(verified.get('status', '')).lower()
        if payment_status == 'succeeded':
            sub = SubscriptionService.activate_subscription_after_payment(
                user=request.user,
                subscription=pending,
                payment_intent_id=payment_intent_id,
            )
            if tx:
                tx.payment_status = Transaction.PAYMENT_SUCCEEDED
                tx.amount = verified.get('amount') or tx.amount
                tx.payment_method = verified.get('payment_method') or tx.payment_method
                tx.save(update_fields=['payment_status', 'amount', 'payment_method'])
            return response.Response(
                {
                    'message': 'Subscription activated successfully.',
                    'subscription': UserSubscriptionSerializer(sub).data,
                }
            )

        pending.payment_status = UserSubscription.PAYMENT_FAILED
        pending.status = UserSubscription.STATUS_CANCELLED
        pending.auto_renew = False
        pending.save(update_fields=['payment_status', 'status', 'auto_renew', 'updated_at'])
        if tx:
            tx.payment_status = Transaction.PAYMENT_FAILED
            tx.save(update_fields=['payment_status'])

        return response.Response(
            {'message': 'Payment failed. Subscription not activated.'},
            status=status.HTTP_400_BAD_REQUEST,
        )


class PaymentWebhookAPIView(APIView):
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        payload = request.data if isinstance(request.data, dict) else {}
        signature = request.headers.get('Stripe-Signature', '')
        webhook_secret = (getattr(settings, 'STRIPE_WEBHOOK_SECRET', '') or '').strip()
        if signature and webhook_secret:
            try:
                stripe = PaymentService._stripe()
                event = stripe.Webhook.construct_event(
                    payload=request.body,
                    sig_header=signature,
                    secret=webhook_secret,
                )
                payload = event or {}
            except Exception:
                return response.Response({'message': 'Invalid webhook signature'}, status=status.HTTP_400_BAD_REQUEST)

        event_type = str(payload.get('type') or '').strip().lower()
        event_data = payload.get('data') or {}
        payment_intent_id = str(
            payload.get('payment_intent_id')
            or (event_data.get('object') or {}).get('id')
            or ''
        ).strip()
        if not payment_intent_id:
            return response.Response({'message': 'payment_intent_id is required'}, status=status.HTTP_400_BAD_REQUEST)

        tx = Transaction.objects.filter(transaction_id=payment_intent_id).select_related('subscription', 'user').first()
        if not tx or not tx.subscription:
            return response.Response({'message': 'Transaction/subscription not found'}, status=status.HTTP_404_NOT_FOUND)

        if event_type in {'payment_intent.succeeded', 'charge.succeeded', 'payment_success'}:
            sub = tx.subscription
            if sub.status == UserSubscription.STATUS_PENDING:
                SubscriptionService.activate_subscription_after_payment(
                    user=sub.user,
                    subscription=sub,
                    payment_intent_id=payment_intent_id,
                )
            tx.payment_status = Transaction.PAYMENT_SUCCEEDED
            tx.save(update_fields=['payment_status'])
            return response.Response({'message': 'Webhook processed: payment succeeded.'})

        if event_type in {'payment_intent.payment_failed', 'payment_failed', 'charge.failed'}:
            sub = tx.subscription
            if sub.status == UserSubscription.STATUS_PENDING:
                sub.payment_status = UserSubscription.PAYMENT_FAILED
                sub.status = UserSubscription.STATUS_CANCELLED
                sub.auto_renew = False
                sub.save(update_fields=['payment_status', 'status', 'auto_renew', 'updated_at'])
            tx.payment_status = Transaction.PAYMENT_FAILED
            tx.save(update_fields=['payment_status'])
            return response.Response({'message': 'Webhook processed: payment failed.'})

        return response.Response({'message': 'Webhook received. No action for event type.'})


class CancelSubscriptionAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = CancelSubscriptionRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        immediate = serializer.validated_data['immediate']
        current = SubscriptionService.get_active_subscription(request.user)
        if not current:
            return response.Response({'message': 'No active subscription found.'}, status=status.HTTP_404_NOT_FOUND)
        SubscriptionService.cancel_subscription(subscription=current, immediate=immediate)
        return response.Response({'message': 'Subscription cancelled successfully.'})


class PaymentHistoryAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        rows = Transaction.objects.filter(user=request.user)
        return response.Response({'results': TransactionSerializer(rows, many=True).data})


class AdminAssignSubscriptionAPIView(APIView):
    permission_classes = (permissions.IsAdminUser,)

    def post(self, request):
        serializer = AdminAssignSubscriptionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        user = User.objects.filter(id=data['user_id']).first()
        plan = SubscriptionPlan.objects.filter(id=data['plan_id']).first()
        if not user or not plan:
            return response.Response(
                {'message': 'User or plan not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        now = timezone.now()
        duration_days = data['duration_days']
        UserSubscription.objects.filter(
            user=user,
            status=UserSubscription.STATUS_ACTIVE,
        ).update(status=UserSubscription.STATUS_CANCELLED, auto_renew=False)

        sub = UserSubscription.objects.create(
            user=user,
            plan=plan,
            start_date=now,
            end_date=now + timedelta(days=duration_days),
            status=data['status'],
            payment_status=data['payment_status'],
            auto_renew=bool(data['auto_renew']),
        )

        return response.Response(
            {
                'message': 'Subscription assigned successfully.',
                'subscription': UserSubscriptionSerializer(sub).data,
            },
            status=status.HTTP_201_CREATED,
        )
