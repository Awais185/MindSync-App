from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('users', '0027_parent_schedule_notification_events'),
    ]

    operations = [
        migrations.CreateModel(
            name='UserAIWellnessRecommendation',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('summary_text', models.TextField(blank=True, default='')),
                ('lines', models.JSONField(blank=True, default=list)),
                ('risk_level', models.CharField(blank=True, default='unknown', max_length=16)),
                ('main_issues', models.JSONField(blank=True, default=list)),
                ('source', models.CharField(blank=True, default='fallback', max_length=32)),
                ('report_window_end', models.DateField(blank=True, null=True)),
                ('generated_at', models.DateTimeField(db_index=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'user',
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='ai_wellness_recommendation',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'verbose_name': 'AI wellness recommendation',
            },
        ),
    ]
