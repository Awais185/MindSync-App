# Parent / child linking and app blocking

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('users', '0006_video_chunk_analysis'),
    ]

    operations = [
        migrations.CreateModel(
            name='ParentChildLink',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('label', models.CharField(blank=True, help_text='e.g. Sarah’s phone', max_length=120)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                (
                    'child',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='parent_child_links_as_child',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'parent',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='parent_child_links_as_parent',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'unique_together': {('parent', 'child')},
            },
        ),
        migrations.CreateModel(
            name='ChildReportedApp',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('package_name', models.CharField(db_index=True, max_length=200)),
                ('app_label', models.CharField(blank=True, max_length=300)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'child_user',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='reported_apps',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'ordering': ['app_label'],
                'unique_together': {('child_user', 'package_name')},
            },
        ),
        migrations.CreateModel(
            name='BlockedAppPackage',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('package_name', models.CharField(db_index=True, max_length=200)),
                ('blocked', models.BooleanField(default=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'child_user',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='blocked_app_packages',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'ordering': ['package_name'],
                'unique_together': {('child_user', 'package_name')},
            },
        ),
    ]
