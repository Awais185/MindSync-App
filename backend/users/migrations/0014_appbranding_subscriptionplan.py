from django.db import migrations, models


def seed_branding_and_plans(apps, schema_editor):
    AppBranding = apps.get_model('users', 'AppBranding')
    SubscriptionPlan = apps.get_model('users', 'SubscriptionPlan')

    AppBranding.objects.get_or_create(
        pk=1,
        defaults={
            'app_name': 'MindSync',
            'welcome_tagline': 'AI-Powered Emotional Wellness',
        },
    )

    plans = [
        {
            'slug': 'basic',
            'title': 'Basic',
            'subtitle': 'For daily starters',
            'description': 'Core tools for everyday wellbeing tracking.',
            'price_monthly': '9.00',
            'features': [
                'Mood Tracking',
                'Daily Insights',
                'Basic Focus Tools',
                'Community Access',
            ],
            'button_label': 'Go Basic',
            'badge': '',
            'is_featured': False,
            'sort_order': 1,
        },
        {
            'slug': 'standard',
            'title': 'Standard',
            'subtitle': 'For growth seekers',
            'description': 'More guidance, richer reports, and family support.',
            'price_monthly': '19.00',
            'features': [
                'Priority AI Response',
                'Weekly Reports',
                'Guided Sessions',
                'Family Sync (2 Users)',
            ],
            'button_label': 'Go Standard',
            'badge': '',
            'is_featured': False,
            'sort_order': 2,
        },
        {
            'slug': 'premium',
            'title': 'Premium',
            'subtitle': 'For power synchronizers',
            'description': 'Advanced support, deeper insights, and premium coaching.',
            'price_monthly': '29.00',
            'features': [
                'Priority AI Response',
                'Family Sync (6 Users)',
                'Neural Landscapes',
                '1-on-1 Monthly Coaching',
            ],
            'button_label': 'Go Premium',
            'badge': 'MOST POPULAR',
            'is_featured': True,
            'sort_order': 3,
        },
    ]

    for plan in plans:
        SubscriptionPlan.objects.get_or_create(slug=plan['slug'], defaults=plan)


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0013_rename_users_video_user_id_0f230e_idx_users_video_user_id_a0975e_idx_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='AppBranding',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('app_name', models.CharField(default='MindSync', max_length=120)),
                ('logo', models.ImageField(blank=True, null=True, upload_to='branding/')),
                ('welcome_tagline', models.CharField(blank=True, default='AI-Powered Emotional Wellness', max_length=200)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'verbose_name': 'App Branding',
                'verbose_name_plural': 'App Branding',
            },
        ),
        migrations.CreateModel(
            name='SubscriptionPlan',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('slug', models.SlugField(max_length=40, unique=True)),
                ('title', models.CharField(max_length=80)),
                ('subtitle', models.CharField(blank=True, max_length=160)),
                ('description', models.TextField(blank=True)),
                ('price_monthly', models.DecimalField(decimal_places=2, default=0, max_digits=8)),
                ('features', models.JSONField(blank=True, default=list)),
                ('button_label', models.CharField(default='Choose Plan', max_length=80)),
                ('badge', models.CharField(blank=True, max_length=80)),
                ('is_featured', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('sort_order', models.PositiveIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'ordering': ['sort_order', 'id'],
            },
        ),
        migrations.RunPython(seed_branding_and_plans, migrations.RunPython.noop),
    ]
