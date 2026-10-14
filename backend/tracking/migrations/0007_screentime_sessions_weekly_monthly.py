from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('tracking', '0004_videoclip_chunk_index'),
    ]

    operations = [
        migrations.CreateModel(
            name='ScreenTimeSession',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('date', models.DateField(db_index=True)),
                ('total_ms', models.PositiveBigIntegerField(default=0)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='screen_time_sessions', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'screen_time_sessions',
                'ordering': ['-date'],
            },
        ),
        migrations.CreateModel(
            name='ScreenTimeWeekly',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('week_start', models.DateField(db_index=True)),
                ('total_ms', models.PositiveBigIntegerField(default=0)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='screen_time_weekly', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'screen_time_weekly',
            },
        ),
        migrations.CreateModel(
            name='ScreenTimeMonthly',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('year_month', models.CharField(db_index=True, max_length=7)),
                ('total_ms', models.PositiveBigIntegerField(default=0)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='screen_time_monthly', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'screen_time_monthly',
            },
        ),
        migrations.AddConstraint(
            model_name='screentimesession',
            constraint=models.UniqueConstraint(fields=('user', 'date'), name='uniq_screen_time_session_user_date'),
        ),
        migrations.AddConstraint(
            model_name='screentimeweekly',
            constraint=models.UniqueConstraint(fields=('user', 'week_start'), name='uniq_screen_time_weekly_user_week'),
        ),
        migrations.AddConstraint(
            model_name='screentimemonthly',
            constraint=models.UniqueConstraint(fields=('user', 'year_month'), name='uniq_screen_time_monthly_user_ym'),
        ),
    ]
