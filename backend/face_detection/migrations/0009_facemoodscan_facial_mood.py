from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import face_detection.models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("face_detection", "0008_rename_face_analysis_user_created_idx_face_analys_user_id_898b2f_idx_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="facialexpressioncapture",
            name="mood",
            field=models.JSONField(blank=True, help_text="Image/video mood detector output when identity matched", null=True),
        ),
        migrations.CreateModel(
            name="FaceMoodScan",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("mood", models.JSONField(blank=True, default=dict)),
                ("modality", models.CharField(choices=[("image", "Image"), ("video", "Video")], db_index=True, max_length=16)),
                ("matched", models.BooleanField(default=True)),
                ("source", models.CharField(db_index=True, default="verify_track", max_length=32)),
                ("capture_image", models.ImageField(blank=True, null=True, upload_to=face_detection.models._face_mood_image_upload_to)),
                ("capture_video", models.FileField(blank=True, null=True, upload_to=face_detection.models._face_mood_video_upload_to)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="face_mood_scans", to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "db_table": "face_mood_scan",
                "ordering": ["-created_at"],
                "indexes": [models.Index(fields=["user", "created_at"], name="face_mood_scan_user_created_idx")],
            },
        ),
    ]
