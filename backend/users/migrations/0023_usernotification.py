from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('users', '0022_userprofile_google_auth'),
    ]

    operations = [
        migrations.CreateModel(
            name='UserNotification',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('event_type', models.CharField(
                    choices=[
                        ('welcome', 'Welcome'),
                        ('weekly_report', 'Weekly report'),
                        ('password_reset_requested', 'Password reset requested'),
                        ('password_changed', 'Password changed'),
                        ('low_wellbeing', 'Low wellbeing'),
                    ],
                    db_index=True,
                    max_length=40,
                )),
                ('title', models.CharField(max_length=200)),
                ('body', models.TextField()),
                ('action_route', models.CharField(blank=True, default='', max_length=80)),
                ('action_label', models.CharField(blank=True, default='', max_length=80)),
                ('priority', models.PositiveSmallIntegerField(default=0)),
                ('is_read', models.BooleanField(db_index=True, default=False)),
                ('dedupe_key', models.CharField(blank=True, db_index=True, default='', max_length=120)),
                ('created_at', models.DateTimeField(auto_now_add=True, db_index=True)),
                ('user', models.ForeignKey(
                    on_delete=models.deletion.CASCADE,
                    related_name='notifications',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='usernotification',
            index=models.Index(fields=['user', '-created_at'], name='users_usern_user_id_6a8f2d_idx'),
        ),
        migrations.AddIndex(
            model_name='usernotification',
            index=models.Index(fields=['user', 'is_read'], name='users_usern_user_id_7b1c9e_idx'),
        ),
        migrations.AddConstraint(
            model_name='usernotification',
            constraint=models.UniqueConstraint(
                condition=models.Q(('dedupe_key', ''), _negated=True),
                fields=('user', 'dedupe_key'),
                name='uniq_user_notification_dedupe',
            ),
        ),
    ]
