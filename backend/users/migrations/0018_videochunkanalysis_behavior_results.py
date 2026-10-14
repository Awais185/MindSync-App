from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0017_alter_videochunkanalysis_script_text'),
    ]

    operations = [
        migrations.AddField(
            model_name='videochunkanalysis',
            name='behavior_results',
            field=models.JSONField(blank=True, default=dict),
        ),
    ]
