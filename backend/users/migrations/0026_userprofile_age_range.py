from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0025_blockedapppackage_blocked_default_false"),
    ]

    operations = [
        migrations.AddField(
            model_name="userprofile",
            name="age_range",
            field=models.CharField(
                blank=True,
                choices=[
                    ("4 - 15 years", "4 - 15 years"),
                    ("16 - 30 years", "16 - 30 years"),
                    ("30+ years", "30+ years"),
                ],
                default="",
                help_text="Used to gate adult ML models in background (16+ only).",
                max_length=32,
            ),
        ),
    ]
