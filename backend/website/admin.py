from django.contrib import admin
from .models import ContactSubmission, NewsletterSubscriber


@admin.register(ContactSubmission)
class ContactSubmissionAdmin(admin.ModelAdmin):
    list_display = ('full_name', 'email', 'inquiry_type', 'status', 'created_at')
    list_filter = ('status', 'inquiry_type', 'created_at')
    search_fields = ('full_name', 'email', 'message')
    readonly_fields = ('ip_address', 'user_agent', 'created_at', 'updated_at')
    list_editable = ('status',)
    ordering = ('-created_at',)


@admin.register(NewsletterSubscriber)
class NewsletterSubscriberAdmin(admin.ModelAdmin):
    list_display = ('email', 'is_active', 'subscribed_at')
    list_filter = ('is_active', 'subscribed_at')
    search_fields = ('email',)
    readonly_fields = ('ip_address', 'subscribed_at', 'unsubscribed_at')
    list_editable = ('is_active',)