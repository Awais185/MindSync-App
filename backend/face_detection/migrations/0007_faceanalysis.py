from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('face_detection', '0006_facialexpressioncapture'),
    ]

    operations = [
        migrations.CreateModel(
            name='FaceAnalysis',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ('source_package', models.CharField(blank=True, default='', max_length=200)),
                ('source_type', models.CharField(blank=True, default='video_watch', max_length=32)),
                ('match_score', models.FloatField(blank=True, null=True)),
                ('emotion_label', models.CharField(blank=True, default='', max_length=32)),
                ('confidence_score', models.FloatField(blank=True, null=True)),
                ('action_units', models.JSONField(blank=True, default=list)),
                ('head_pose', models.JSONField(blank=True, default=dict)),
                ('gaze_data', models.JSONField(blank=True, default=dict)),
                ('openface_payload', models.JSONField(blank=True, default=dict)),
                ('stress_score', models.PositiveSmallIntegerField(default=0)),
                ('anxiety_score', models.PositiveSmallIntegerField(default=0)),
                ('depression_score', models.PositiveSmallIntegerField(default=0)),
                ('processing_error', models.TextField(blank=True, default='')),
                ('created_at', models.DateTimeField(auto_now_add=True, db_index=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='face_analyses', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'face_analysis',
                'ordering': ['-created_at'],
                'indexes': [models.Index(fields=['user', 'created_at'], name='face_analysis_user_created_idx')],
            },
        ),
    ]
