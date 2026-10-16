from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("tracking", "0008_screentime_is_finalized_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="screentimesession",
            name="mood",
            field=models.CharField(blank=True, default="", max_length=64),
        ),
        migrations.AddField(
            model_name="screentimesession",
            name="stress_score",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="screentimesession",
            name="anxiety_score",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="screentimesession",
            name="depression_score",
            field=models.PositiveSmallIntegerField(default=0),
        ),
    ]
