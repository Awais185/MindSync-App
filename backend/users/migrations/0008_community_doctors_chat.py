from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0007_parental_control'),
    ]

    operations = [
        migrations.CreateModel(
            name='DoctorProfile',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('full_name', models.CharField(max_length=150)),
                ('designation', models.CharField(max_length=120)),
                ('experience_years', models.PositiveIntegerField(default=0)),
                ('specialist', models.CharField(max_length=120)),
                ('contact_number', models.CharField(max_length=40)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'ordering': ['full_name'],
            },
        ),
        migrations.CreateModel(
            name='CommunityPost',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('content', models.TextField()),
                ('category', models.CharField(choices=[('stress', 'Stress'), ('selfcare', 'SelfCare'), ('wellness', 'Wellness'), ('mindfulness', 'Mindfulness'), ('other', 'Other')], default='wellness', max_length=30)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='community_posts', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-created_at'],
                'indexes': [models.Index(fields=['category', 'created_at'], name='users_commu_categor_18fca7_idx')],
            },
        ),
        migrations.CreateModel(
            name='TrustedContact',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=150)),
                ('relationship', models.CharField(max_length=80)),
                ('contact_number', models.CharField(max_length=40)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trusted_contacts', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['name'],
            },
        ),
        migrations.CreateModel(
            name='DoctorChatMessage',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('sender', models.CharField(choices=[('user', 'User'), ('doctor', 'Doctor')], max_length=20)),
                ('message', models.TextField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('doctor', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='messages', to='users.doctorprofile')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='doctor_messages', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['created_at'],
                'indexes': [models.Index(fields=['user', 'doctor', 'created_at'], name='users_docto_user_id_395a24_idx')],
            },
        ),
    ]
