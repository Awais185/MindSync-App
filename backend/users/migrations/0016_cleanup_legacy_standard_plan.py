from django.db import migrations


def cleanup_legacy_plan_rows(apps, schema_editor):
    SubscriptionPlan = apps.get_model('users', 'SubscriptionPlan')

    basic, _ = SubscriptionPlan.objects.update_or_create(
        slug='basic',
        defaults={
            'title': 'Basic',
            'subtitle': 'For daily starters',
            'description': 'Core tools for everyday wellbeing tracking.',
            'price_monthly': '3.00',
            'features': [
                'Limited Emotion Detection (max 2 scans/day)',
                'Basic Mood Tracking',
                'Screen Time Tracking',
                'Content Monitoring',
                'Day/Week/Month screen analytics',
                'Content watch type analytics',
                'Contact with Real-time Psychologist',
                'Ads included',
            ],
            'button_label': 'Go Basic',
            'badge': '',
            'is_featured': False,
            'is_active': True,
            'sort_order': 1,
        },
    )
    premium, _ = SubscriptionPlan.objects.update_or_create(
        slug='premium',
        defaults={
            'title': 'Premium',
            'subtitle': 'All features unlocked',
            'description': 'Includes Basic + full behavioral insights and protection.',
            'price_monthly': '6.00',
            'features': [
                'Limited Emotion Detection (max 2 scans/day)',
                'Basic Mood Tracking',
                'Screen Time Tracking',
                'Content Monitoring',
                'Day/Week/Month screen analytics',
                'Content watch type analytics',
                'Contact with Real-time Psychologist',
                'Ads included',
                'Full Emotion Detection',
                'Weekly Reports',
                'No Ads',
                'Personalized Suggestions',
                'Digital Psychologist (LLM chat)',
                'Mental Health Monitoring',
                'Advanced AI Insights',
                'Monthly Reports',
                'Therapist Recommendations',
                'Priority Support',
                'Parental Control',
                'Full App Access',
            ],
            'button_label': 'Go Premium',
            'badge': 'MOST POPULAR',
            'is_featured': True,
            'is_active': True,
            'sort_order': 2,
        },
    )

    SubscriptionPlan.objects.filter(slug='standard').delete()
    SubscriptionPlan.objects.exclude(slug__in=['basic', 'premium']).update(is_active=False)
    SubscriptionPlan.objects.filter(slug__in=['basic', 'premium']).update(is_active=True)


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0015_video_chunk_behavior_fields'),
    ]

    operations = [
        migrations.RunPython(cleanup_legacy_plan_rows, migrations.RunPython.noop),
    ]
