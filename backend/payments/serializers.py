from rest_framework import serializers

from subscriptions.models import Transaction
from subscriptions.serializers import UserSubscriptionSerializer


class CreatePaymentIntentSerializer(serializers.Serializer):
    plan_id = serializers.CharField(max_length=50)


class ConfirmSubscriptionSerializer(serializers.Serializer):
    payment_intent_id = serializers.CharField(max_length=100)
    plan_id = serializers.CharField(max_length=50)


def subscription_payload_from_user_sub(sub) -> dict:
    plan = sub.plan
    amount_cents = int(plan.price_usd * 100)
    return {
        'plan_name': plan.code,
        'plan_display_name': plan.name,
        'amount_paid': amount_cents,
        'currency': 'usd',
        'stripe_customer_id': sub.stripe_customer_id or '',
        'stripe_payment_intent_id': sub.stripe_payment_intent_id or '',
        'status': sub.status,
        'started_at': sub.start_date,
        'expires_at': sub.end_date,
        'is_active': sub.is_active,
        'subscription': UserSubscriptionSerializer(sub).data,
    }


class PaymentHistorySerializer(serializers.ModelSerializer):
    plan_name = serializers.SerializerMethodField()
    paid_at = serializers.DateTimeField(source='created_at', read_only=True)
    stripe_payment_intent_id = serializers.CharField(source='transaction_id', read_only=True)
    status = serializers.CharField(source='payment_status', read_only=True)

    class Meta:
        model = Transaction
        fields = (
            'id',
            'plan_name',
            'amount',
            'currency',
            'status',
            'paid_at',
            'stripe_payment_intent_id',
        )

    def get_plan_name(self, obj):
        if obj.subscription_plan_id:
            return obj.subscription_plan.code
        return ''
