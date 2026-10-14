from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('tracking', '0003_faceverificationevent'),
    ]

    operations = [
        migrations.AddField(
            model_name='videoclip',
            name='chunk_index',
            field=models.PositiveIntegerField(
                default=0,
                help_text='0-based segment index for this screen-recording session (30s chunks).',
            ),
        ),
    ]
