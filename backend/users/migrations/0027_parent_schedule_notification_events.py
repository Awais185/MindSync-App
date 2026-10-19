from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0026_userprofile_age_range'),
    ]

    operations = [
        migrations.AlterField(
            model_name='usernotification',
            name='event_type',
            field=models.CharField(
                choices=[
                    ('welcome', 'Welcome'),
                    ('weekly_report', 'Weekly report'),
                    ('password_reset_requested', 'Password reset requested'),
                    ('password_changed', 'Password changed'),
                    ('low_wellbeing', 'Low wellbeing'),
                    ('parent_bedtime', 'Parent bedtime'),
                    ('parent_wakeup', 'Parent wake-up'),
                ],
                db_index=True,
                max_length=40,
            ),
        ),
    ]
