# Generated manually for FacialExpressionCapture

import django.db.models.deletion
import face_detection.models
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("face_detection", "0005_mentalhealthresult_reaction_openface"),
    ]

    operations = [
        migrations.CreateModel(
            name="FacialExpressionCapture",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("video", models.FileField(upload_to=face_detection.models._facial_expression_upload_to)),
                (
                    "source_type",
                    models.CharField(
                        choices=[
                            ("video_watch", "Video watch"),
                            ("scheduled_background", "Scheduled background"),
                            ("social_media", "Social media"),
                            ("manual_scan", "Manual scan"),
                        ],
                        db_index=True,
                        default="video_watch",
                        max_length=32,
                    ),
                ),
                ("source_app_name", models.CharField(blank=True, default="", max_length=120)),
                ("source_package_name", models.CharField(blank=True, default="", max_length=200)),
                ("duration_seconds", models.PositiveSmallIntegerField(default=20)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("pending", "Pending"),
                            ("processing", "Processing"),
                            ("completed", "Completed"),
                            ("failed", "Failed"),
                        ],
                        db_index=True,
                        default="pending",
                        max_length=16,
                    ),
                ),
                ("processing_error", models.TextField(blank=True, default="")),
                ("stress_score", models.PositiveSmallIntegerField(default=0)),
                ("anxiety_score", models.PositiveSmallIntegerField(default=0)),
                ("depression_score", models.PositiveSmallIntegerField(default=0)),
                ("dominant_state", models.CharField(db_index=True, default="neutral", max_length=32)),
                ("active_aus", models.JSONField(blank=True, default=list)),
                ("au_results", models.JSONField(blank=True, null=True)),
                ("face_match_score", models.FloatField(blank=True, null=True)),
                ("client_timestamp_ms", models.BigIntegerField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("processed_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                ("video_deleted_at", models.DateTimeField(blank=True, null=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="facial_expression_captures",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "facial_expression_capture",
                "ordering": ["-created_at"],
                "indexes": [
                    models.Index(fields=["user", "created_at"], name="facial_expr_user_created_idx"),
                    models.Index(fields=["user", "status"], name="facial_expr_user_status_idx"),
                    models.Index(fields=["status", "created_at"], name="facial_expr_status_created_idx"),
                ],
            },
        ),
    ]
