from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0008_community_doctors_chat'),
    ]

    operations = [
        migrations.AddField(
            model_name='doctorprofile',
            name='account',
            field=models.OneToOneField(
                blank=True,
                help_text='Select doctor login account (email/user).',
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='doctor_profile',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
    ]
