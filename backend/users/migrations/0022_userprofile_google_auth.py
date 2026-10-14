from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0021_usermoodwindow'),
    ]

    operations = [
        migrations.AddField(
            model_name='userprofile',
            name='google_auth',
            field=models.BooleanField(
                default=False,
                help_text='True when the account was created or linked via Google Sign-In.',
            ),
        ),
    ]
