from django.db import migrations


def deactivate_doctor_plan(apps, schema_editor):
    SubscriptionPlan = apps.get_model('subscriptions', 'SubscriptionPlan')
    UserSubscription = apps.get_model('subscriptions', 'UserSubscription')

    doctor_plan = SubscriptionPlan.objects.filter(code='doctor').first()
    if not doctor_plan:
        return

    premium_plan = SubscriptionPlan.objects.filter(code='premium').first()
    active_subs = UserSubscription.objects.filter(
        plan=doctor_plan,
        status='active',
    )
    for sub in active_subs:
        if premium_plan:
            sub.plan = premium_plan
            sub.save(update_fields=['plan'])
        else:
            sub.status = 'cancelled'
            sub.save(update_fields=['status'])

    doctor_plan.is_active = False
    doctor_plan.save(update_fields=['is_active'])


class Migration(migrations.Migration):
    dependencies = [
        ('subscriptions', '0006_rename_subscriptio_user_id_8e2f0a_idx_subscriptio_user_id_9c57a2_idx_and_more'),
    ]

    operations = [
        migrations.RunPython(deactivate_doctor_plan, migrations.RunPython.noop),
    ]
