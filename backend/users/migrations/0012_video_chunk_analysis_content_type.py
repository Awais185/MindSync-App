from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('tracking', '0002_videoclip_analysis_fields'),
        ('users', '0011_community_post_likes_comments'),
    ]

    operations = [
        migrations.AddField(
            model_name='videochunkanalysis',
            name='content_type',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='duration_seconds',
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='platform',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='source_clip',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='analysis_records',
                to='tracking.videoclip',
            ),
        ),
        migrations.AddIndex(
            model_name='videochunkanalysis',
            index=models.Index(fields=['user', 'created_at'], name='users_video_user_id_0f230e_idx'),
        ),
        migrations.AddIndex(
            model_name='videochunkanalysis',
            index=models.Index(fields=['platform'], name='users_video_platfor_39df0d_idx'),
        ),
    ]
