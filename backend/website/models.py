from django.db import models


class ContactSubmission(models.Model):
    """Contact form submissions from the website."""
    STATUS_CHOICES = [
        ('new', 'New'),
        ('in_progress', 'In Progress'),
        ('resolved', 'Resolved'),
        ('spam', 'Spam'),
    ]

    INQUIRY_CHOICES = [
        ('general', 'General Inquiry'),
        ('enterprise', 'Enterprise Solutions'),
        ('support', 'Technical Support'),
        ('partnership', 'Partnership'),
        ('press', 'Press'),
    ]

    full_name = models.CharField(max_length=120)
    email = models.EmailField()
    inquiry_type = models.CharField(max_length=20, choices=INQUIRY_CHOICES, default='general')
    message = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='new')

    # Meta
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Contact Submission'
        verbose_name_plural = 'Contact Submissions'

    def __str__(self):
        return f"{self.full_name} — {self.email} ({self.get_inquiry_type_display()})"


class NewsletterSubscriber(models.Model):
    """Newsletter email subscribers."""
    email = models.EmailField(unique=True)
    is_active = models.BooleanField(default=True)

    # Meta
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    subscribed_at = models.DateTimeField(auto_now_add=True)
    unsubscribed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-subscribed_at']
        verbose_name = 'Newsletter Subscriber'
        verbose_name_plural = 'Newsletter Subscribers'

    def __str__(self):
        return self.email