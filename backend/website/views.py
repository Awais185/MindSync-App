
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny

from .models import ContactSubmission, NewsletterSubscriber
from .serializers import (
    ContactSubmissionSerializer,
    NewsletterSubscriberSerializer,
)


def _client_ip(request):
    """Extract client IP from request, handling proxies."""
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')


class ContactSubmissionCreateView(generics.CreateAPIView):
    """POST /api/website/contact/ — Submit contact form."""
    queryset = ContactSubmission.objects.all()
    serializer_class = ContactSubmissionSerializer
    permission_classes = [AllowAny]

    def perform_create(self, serializer):
        serializer.save(
            ip_address=_client_ip(self.request),
            user_agent=self.request.META.get('HTTP_USER_AGENT', '')[:500],
        )

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        return Response(
            {
                'success': True,
                'message': 'Thank you — your message has been received. We will respond shortly.',
                'data': serializer.data,
            },
            status=status.HTTP_201_CREATED,
        )


class NewsletterSubscribeView(generics.CreateAPIView):
    """POST /api/website/newsletter/ — Subscribe to newsletter."""
    queryset = NewsletterSubscriber.objects.all()
    serializer_class = NewsletterSubscriberSerializer
    permission_classes = [AllowAny]

    def perform_create(self, serializer):
        serializer.save(ip_address=_client_ip(self.request))

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        return Response(
            {
                'success': True,
                'message': 'You are subscribed! Welcome to the MindSync community.',
                'data': serializer.data,
            },
            status=status.HTTP_201_CREATED,
        )


class WebsiteHealthView(APIView):
    """GET /api/website/health/ — quick ping for the frontend."""
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({
            'status': 'ok',
            'service': 'website',
            'contact_submissions': ContactSubmission.objects.count(),
            'newsletter_subscribers': NewsletterSubscriber.objects.filter(is_active=True).count(),
        })