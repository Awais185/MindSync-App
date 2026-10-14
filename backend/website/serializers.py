from rest_framework import serializers
from .models import ContactSubmission, NewsletterSubscriber


class ContactSubmissionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ContactSubmission
        fields = [
            'id', 'full_name', 'email', 'inquiry_type',
            'message', 'created_at',
        ]
        read_only_fields = ['id', 'created_at']

    def validate_full_name(self, value):
        if len(value.strip()) < 2:
            raise serializers.ValidationError('Full name must be at least 2 characters.')
        return value.strip()

    def validate_message(self, value):
        if len(value.strip()) < 10:
            raise serializers.ValidationError('Message must be at least 10 characters.')
        return value.strip()


class NewsletterSubscriberSerializer(serializers.ModelSerializer):
    class Meta:
        model = NewsletterSubscriber
        fields = ['id', 'email', 'subscribed_at']
        read_only_fields = ['id', 'subscribed_at']

    def validate_email(self, value):
        value = value.strip().lower()
        if NewsletterSubscriber.objects.filter(email=value).exists():
            raise serializers.ValidationError('This email is already subscribed.')
        return value