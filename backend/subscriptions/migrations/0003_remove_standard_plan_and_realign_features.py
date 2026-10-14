from django.db import migrations


def migrate_to_basic_premium(apps, schema_editor):
    SubscriptionPlan = apps.get_model('subscriptions', 'SubscriptionPlan')
    UserSubscription = apps.get_model('subscriptions', 'UserSubscription')

    basic_features = [
        'emotion_detection_limited',
        'basic_mood_tracking',
        'screen_time',
        'content_monitoring',
        'chat_realtime_psychologist',
        'analytics_day_week_month',
        'ads_included',
    ]
    premium_features = [
        # Basic
        'emotion_detection_limited',
        'basic_mood_tracking',
        'screen_time',
        'content_monitoring',
        'chat_realtime_psychologist',
        'analytics_day_week_month',
        'ads_included',
        # Standard (merged)
        'emotion_detection_full',
        'weekly_reports',
        'no_ads',
        'personalized_suggestions',
        'chat_digital_psychologist',
        'mental_health_monitoring',
        # Premium
        'advanced_ai_insights',
        'monthly_mental_health_reports',
        'therapist_recommendation',
        'priority_support',
        'parental_control',
        'full_app_access',
    ]

    basic, _ = SubscriptionPlan.objects.update_or_create(
        code='basic',
        defaults={
            'name': 'Basic',
            'price_usd': '3.00',
            'billing_cycle': 'monthly',
            'features': basic_features,
            'is_active': True,
        },
    )
    premium, _ = SubscriptionPlan.objects.update_or_create(
        code='premium',
        defaults={
            'name': 'Premium',
            'price_usd': '6.00',
            'billing_cycle': 'monthly',
            'features': premium_features,
            'is_active': True,
        },
    )

    standard = SubscriptionPlan.objects.filter(code='standard').first()
    if standard:
        # Move historical subscriptions off standard before deleting it.
        UserSubscription.objects.filter(plan=standard).update(plan=premium)
        standard.delete()

    # Ensure no other paid plan code remains active by mistake.
    SubscriptionPlan.objects.exclude(code__in=['basic', 'premium']).update(is_active=False)
    # Keep explicit active state for target plans.
    SubscriptionPlan.objects.filter(code__in=['basic', 'premium']).update(is_active=True)


class Migration(migrations.Migration):
    dependencies = [
        ('subscriptions', '0002_seed_default_plans'),
    ]

    operations = [
        migrations.RunPython(migrate_to_basic_premium, migrations.RunPython.noop),
    ]
