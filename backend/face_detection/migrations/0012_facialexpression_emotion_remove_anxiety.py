from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("face_detection", "0011_mentalhealthresult_mood"),
    ]

    operations = [
        migrations.AddField(
            model_name="facialexpressioncapture",
            name="emotion",
            field=models.CharField(
                blank=True,
                default="",
                max_length=64,
                help_text="Adult emotion model label from background video processing.",
            ),
        ),
        migrations.RemoveField(
            model_name="facialexpressioncapture",
            name="anxiety_score",
        ),
    ]
