from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0014_appbranding_subscriptionplan'),
    ]

    operations = [
        migrations.AddField(
            model_name='videochunkanalysis',
            name='behavior_analyzed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='behavior_result',
            field=models.CharField(blank=True, default='', max_length=64),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='classification_outputs',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='confidence_score',
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='videochunkanalysis',
            name='prediction_error',
            field=models.TextField(blank=True, default=''),
        ),
    ]
