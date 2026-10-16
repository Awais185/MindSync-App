from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0024_remove_parentchildlink_users_paren_parent__2fca78_idx_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='blockedapppackage',
            name='blocked',
            field=models.BooleanField(default=False),
        ),
    ]
