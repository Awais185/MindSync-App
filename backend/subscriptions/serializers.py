from __future__ import annotations

from decimal import Decimal

from rest_framework import serializers

from .models import Payment, SubscriptionPlan, Transaction, UserSubscription


class SubscriptionPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionPlan
        fields = (
            'id',
            'name',
            'code',
            'price_usd',
            'duration_days',
            'billing_cycle',
            'features',
            'is_active',
        )


class UserSubscriptionSerializer(serializers.ModelSerializer):
    plan = SubscriptionPlanSerializer(read_only=True)
    is_active = serializers.BooleanField(read_only=True)

    class Meta:
        model = UserSubscription
        fields = (
            'id',
            'plan',
            'start_date',
            'end_date',
            'status',
            'payment_status',
            'auto_renew',
            'is_active',
        )


class SubscribeRequestSerializer(serializers.Serializer):
    plan_id = serializers.IntegerField()
    payment_method = serializers.CharField(required=False, allow_blank=True, default='card')
    coupon_code = serializers.CharField(required=False, allow_blank=True, default='')
    auto_renew = serializers.BooleanField(default=False)


class UpgradeRequestSerializer(serializers.Serializer):
    plan_id = serializers.IntegerField()
    payment_method = serializers.CharField(required=False, allow_blank=True, default='card')
    coupon_code = serializers.CharField(required=False, allow_blank=True, default='')
    auto_renew = serializers.BooleanField(default=False)


class CreatePaymentRequestSerializer(serializers.Serializer):
    FLOW_SUBSCRIBE = 'subscribe'
    FLOW_UPGRADE = 'upgrade'
    FLOW_CHOICES = (
        (FLOW_SUBSCRIBE, 'Subscribe'),
        (FLOW_UPGRADE, 'Upgrade'),
    )

    plan_id = serializers.IntegerField()
    flow = serializers.ChoiceField(choices=FLOW_CHOICES, default=FLOW_SUBSCRIBE)
    payment_gateway = serializers.CharField(required=False, allow_blank=True, default='stripe')
    payment_method = serializers.CharField(required=False, allow_blank=True, default='card')
    coupon_code = serializers.CharField(required=False, allow_blank=True, default='')
    auto_renew = serializers.BooleanField(default=False)


class CancelSubscriptionRequestSerializer(serializers.Serializer):
    immediate = serializers.BooleanField(default=False)


class ConfirmPaymentSerializer(serializers.Serializer):
    payment_intent_id = serializers.CharField()


class TransactionSerializer(serializers.ModelSerializer):
    subscription_plan = SubscriptionPlanSerializer(read_only=True)

    class Meta:
        model = Transaction
        fields = (
            'id',
            'subscription_plan',
            'amount',
            'currency',
            'payment_method',
            'transaction_id',
            'payment_status',
            'coupon_code',
            'created_at',
        )


class CreateManualPaymentSerializer(serializers.Serializer):
    plan_id = serializers.IntegerField()
    payment_method = serializers.CharField(required=False, allow_blank=True, default='bank_transfer')
    transaction_reference = serializers.CharField(required=False, allow_blank=True, default='')


class UploadPaymentProofSerializer(serializers.Serializer):
    payment_id = serializers.IntegerField()
    transaction_reference = serializers.CharField(required=False, allow_blank=True, default='')
    screenshot_proof = serializers.ImageField(required=False)


class PaymentSerializer(serializers.ModelSerializer):
    plan = SubscriptionPlanSerializer(read_only=True)
    screenshot_url = serializers.SerializerMethodField()

    class Meta:
        model = Payment
        fields = (
            'id',
            'plan',
            'subscription',
            'amount',
            'payment_method',
            'transaction_reference',
            'screenshot_url',
            'status',
            'created_at',
            'reviewed_at',
        )

    def get_screenshot_url(self, obj):
        if not obj.screenshot_proof:
            return ''
        request = self.context.get('request')
        if request:
            return request.build_absolute_uri(obj.screenshot_proof.url)
        return obj.screenshot_proof.url


class AdminAssignSubscriptionSerializer(serializers.Serializer):
    user_id = serializers.IntegerField()
    plan_id = serializers.IntegerField()
    auto_renew = serializers.BooleanField(default=False)
    status = serializers.ChoiceField(choices=UserSubscription.STATUS_CHOICES, default=UserSubscription.STATUS_ACTIVE)
    payment_status = serializers.ChoiceField(
        choices=UserSubscription.PAYMENT_STATUS_CHOICES,
        default=UserSubscription.PAYMENT_PAID,
    )
    duration_days = serializers.IntegerField(min_value=1, default=30)
