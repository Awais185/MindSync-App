from django.conf import settings
from django.contrib import admin
from django.utils.html import format_html

from .models import Payment, SubscriptionPlan, Transaction, UserSubscription


def _stripe_payment_link(payment_intent_id: str) -> str:
    pi = (payment_intent_id or '').strip()
    if not pi.startswith('pi_'):
        return '—'
    base = 'https://dashboard.stripe.com/test/payments' if getattr(settings, 'DEBUG', True) else 'https://dashboard.stripe.com/payments'
    return format_html('<a href="{}/{}" target="_blank" rel="noopener">Stripe</a>', base, pi)


@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'name',
        'code',
        'price_usd',
        'duration_days',
        'billing_cycle',
        'is_active',
        'updated_at',
    )
    list_filter = ('billing_cycle', 'is_active')
    search_fields = ('name', 'code')


@admin.register(UserSubscription)
class UserSubscriptionAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'plan',
        'status',
        'payment_status',
        'auto_renew',
        'start_date',
        'end_date',
        'stripe_payment_intent_id',
        'stripe_dashboard_link',
    )
    list_filter = ('status', 'payment_status', 'auto_renew', 'plan')
    search_fields = ('user__username', 'user__email', 'plan__name', 'stripe_payment_intent_id')
    autocomplete_fields = ('user', 'plan')
    readonly_fields = (
        'stripe_customer_id',
        'stripe_payment_intent_id',
        'stripe_subscription_id',
        'created_at',
        'updated_at',
    )

    @admin.display(description='Stripe')
    def stripe_dashboard_link(self, obj):
        return _stripe_payment_link(obj.stripe_payment_intent_id)


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'plan',
        'amount',
        'payment_method',
        'transaction_reference',
        'status',
        'created_at',
        'reviewed_at',
    )
    list_filter = ('status', 'payment_method', 'plan')
    search_fields = ('user__username', 'user__email', 'transaction_reference')
    autocomplete_fields = ('user', 'plan', 'subscription', 'reviewed_by')
    readonly_fields = ('created_at', 'updated_at', 'reviewed_at')


@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'subscription_plan',
        'amount',
        'payment_method',
        'transaction_id',
        'payment_status',
        'created_at',
        'stripe_dashboard_link',
    )
    list_filter = ('payment_status', 'payment_method', 'subscription_plan')
    search_fields = ('user__username', 'user__email', 'transaction_id')
    autocomplete_fields = ('user', 'subscription', 'subscription_plan', 'manual_payment')
    readonly_fields = ('transaction_id', 'created_at')

    @admin.display(description='Stripe')
    def stripe_dashboard_link(self, obj):
        return _stripe_payment_link(obj.transaction_id)
