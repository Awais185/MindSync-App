# Generated manually for MindSync video pipeline

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('users', '0005_screen_usage_event'),
    ]

    operations = [
        migrations.CreateModel(
            name='VideoChunkAnalysis',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('chunk_id', models.CharField(db_index=True, max_length=64)),
                ('session_id', models.CharField(db_index=True, max_length=64)),
                ('script_text', models.TextField()),
                ('source_package', models.CharField(blank=True, max_length=200, null=True)),
                ('client_created_at_ms', models.BigIntegerField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                (
                    'user',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='video_chunk_analyses',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
    ]
