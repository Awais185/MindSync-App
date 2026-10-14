from django.db import migrations


def seed_doctor_plan(apps, schema_editor):
    SubscriptionPlan = apps.get_model('subscriptions', 'SubscriptionPlan')
    SubscriptionPlan.objects.update_or_create(
        code='doctor',
        defaults={
            'name': 'Doctor',
            'price_usd': '5.00',
            'billing_cycle': 'monthly',
            'duration_days': 30,
            'is_active': True,
            'features': [
                'full_app_access',
                'doctor_patient_inbox',
                'doctor_appointments',
                'doctor_patient_assist',
                'mental_health_monitoring',
                'weekly_reports',
                'advanced_ai_insights',
                'priority_support',
                'no_ads',
            ],
        },
    )


class Migration(migrations.Migration):
    dependencies = [
        ('subscriptions', '0004_manual_payment_and_duration'),
    ]

    operations = [
        migrations.RunPython(seed_doctor_plan, migrations.RunPython.noop),
    ]
