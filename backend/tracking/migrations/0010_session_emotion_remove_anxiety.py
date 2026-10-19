from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("tracking", "0009_screentimesession_mental_health_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="screentimesession",
            name="emotion",
            field=models.CharField(blank=True, default="", max_length=64),
        ),
        migrations.RemoveField(
            model_name="screentimesession",
            name="anxiety_score",
        ),
    ]
