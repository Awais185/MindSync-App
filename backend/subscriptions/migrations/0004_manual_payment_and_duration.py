# Generated manually for MindSync manual payments

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('subscriptions', '0003_remove_standard_plan_and_realign_features'),
    ]

    operations = [
        migrations.AddField(
            model_name='subscriptionplan',
            name='duration_days',
            field=models.PositiveIntegerField(
                default=30,
                help_text='Subscription length after payment approval.',
            ),
        ),
        migrations.CreateModel(
            name='Payment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('payment_method', models.CharField(default='bank_transfer', max_length=40)),
                ('transaction_reference', models.CharField(blank=True, default='', max_length=120)),
                ('screenshot_proof', models.ImageField(blank=True, null=True, upload_to='payments/proofs/%Y/%m/')),
                ('status', models.CharField(
                    choices=[('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')],
                    default='pending',
                    max_length=20,
                )),
                ('reviewed_at', models.DateTimeField(blank=True, null=True)),
                ('admin_note', models.CharField(blank=True, default='', max_length=500)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('plan', models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name='manual_payments',
                    to='subscriptions.subscriptionplan',
                )),
                ('reviewed_by', models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='reviewed_payments',
                    to=settings.AUTH_USER_MODEL,
                )),
                ('subscription', models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='manual_payments',
                    to='subscriptions.usersubscription',
                )),
                ('user', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='manual_payments',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddField(
            model_name='transaction',
            name='manual_payment',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='transactions',
                to='subscriptions.payment',
            ),
        ),
        migrations.AddIndex(
            model_name='payment',
            index=models.Index(fields=['user', 'status'], name='subscriptio_user_id_8e2f0a_idx'),
        ),
        migrations.AddIndex(
            model_name='payment',
            index=models.Index(fields=['status', 'created_at'], name='subscriptio_status_4c8b1d_idx'),
        ),
    ]
