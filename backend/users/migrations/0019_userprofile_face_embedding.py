from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0018_videochunkanalysis_behavior_results"),
    ]

    operations = [
        migrations.AddField(
            model_name="userprofile",
            name="face_embedding",
            field=models.JSONField(blank=True, default=list),
        ),
    ]
