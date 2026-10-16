from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("face_detection", "0010_rename_face_mood_scan_user_created_idx_face_mood_s_user_id_693fbe_idx"),
    ]

    operations = [
        migrations.AddField(
            model_name="mentalhealthresult",
            name="mood",
            field=models.CharField(
                blank=True,
                default="",
                help_text="ResNet18 ensemble emotion label (background captures).",
                max_length=64,
            ),
        ),
    ]
