from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("face_detection", "0004_mentalhealthresult_analyzed_video"),
    ]

    operations = [
        migrations.AddField(
            model_name="mentalhealthresult",
            name="reaction_app_name",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="mentalhealthresult",
            name="reaction_package_name",
            field=models.CharField(blank=True, default="", max_length=200),
        ),
        migrations.AddField(
            model_name="mentalhealthresult",
            name="openface_summary",
            field=models.JSONField(blank=True, null=True),
        ),
    ]
