from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from django.contrib.auth.models import User
from django.db.models import Max

from .models import (
    CommunityPost,
    DoctorProfile,
    DoctorChatMessage,
    TrustedContact,
    CommunityPostLike,
    CommunityPostComment,
)
from .serializers import (
    CommunityPostSerializer,
    DoctorProfileSerializer,
    DoctorChatMessageSerializer,
    TrustedContactSerializer,
    CommunityPostCommentSerializer,
)
from subscriptions.permissions import require_subscription_feature


class CommunityPostsAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        category = (request.query_params.get('category') or '').strip().lower()
        posts = CommunityPost.objects.all()
        if category and category != 'all':
            posts = posts.filter(category=category)
        return Response(CommunityPostSerializer(posts, many=True, context={'request': request}).data)

    def post(self, request):
        serializer = CommunityPostSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        post = CommunityPost.objects.create(
            user=request.user,
            content=serializer.validated_data['content'],
            category=serializer.validated_data.get('category', 'wellness'),
        )
        return Response(
            CommunityPostSerializer(post, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )


class CommunityPostLikeToggleAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def post(self, request, post_id: int):
        post = CommunityPost.objects.filter(id=post_id).first()
        if not post:
            return Response({'detail': 'Post not found.'}, status=status.HTTP_404_NOT_FOUND)

        row = CommunityPostLike.objects.filter(post=post, user=request.user).first()
        if row:
            row.delete()
            liked = False
        else:
            CommunityPostLike.objects.create(post=post, user=request.user)
            liked = True

        return Response(
            {
                'liked': liked,
                'likes_count': CommunityPostLike.objects.filter(post=post).count(),
            }
        )


class CommunityPostCommentsAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request, post_id: int):
        post = CommunityPost.objects.filter(id=post_id).first()
        if not post:
            return Response({'detail': 'Post not found.'}, status=status.HTTP_404_NOT_FOUND)
        comments = CommunityPostComment.objects.filter(post=post)
        return Response(CommunityPostCommentSerializer(comments, many=True).data)

    def post(self, request, post_id: int):
        post = CommunityPost.objects.filter(id=post_id).first()
        if not post:
            return Response({'detail': 'Post not found.'}, status=status.HTTP_404_NOT_FOUND)
        content = (request.data.get('content') or '').strip()
        if not content:
            return Response({'content': ['This field is required.']}, status=status.HTTP_400_BAD_REQUEST)
        comment = CommunityPostComment.objects.create(
            post=post,
            user=request.user,
            content=content,
        )
        return Response(CommunityPostCommentSerializer(comment).data, status=status.HTTP_201_CREATED)


class DoctorsListAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'chat_digital_psychologist',
        'Upgrade to Premium to access doctor contact.',
    )
    def get(self, request):
        doctors = DoctorProfile.objects.filter(is_active=True)
        return Response(DoctorProfileSerializer(doctors, many=True).data)


class TrustedContactsAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        contacts = TrustedContact.objects.filter(user=request.user)
        return Response(TrustedContactSerializer(contacts, many=True).data)

    def post(self, request):
        serializer = TrustedContactSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        contact = TrustedContact.objects.create(
            user=request.user,
            name=serializer.validated_data['name'],
            relationship=serializer.validated_data['relationship'],
            contact_number=serializer.validated_data['contact_number'],
        )
        return Response(TrustedContactSerializer(contact).data, status=status.HTTP_201_CREATED)


class DoctorChatAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    @require_subscription_feature(
        'chat_digital_psychologist',
        'Upgrade to Premium to access doctor contact.',
    )
    def get(self, request, doctor_id: int):
        if not DoctorProfile.objects.filter(id=doctor_id, is_active=True).exists():
            return Response({'detail': 'Doctor not found.'}, status=status.HTTP_404_NOT_FOUND)
        qs = DoctorChatMessage.objects.filter(user=request.user, doctor_id=doctor_id)
        return Response(DoctorChatMessageSerializer(qs, many=True).data)

    @require_subscription_feature(
        'chat_digital_psychologist',
        'Upgrade to Premium to access doctor contact.',
    )
    def post(self, request, doctor_id: int):
        doctor = DoctorProfile.objects.filter(id=doctor_id, is_active=True).first()
        if not doctor:
            return Response({'detail': 'Doctor not found.'}, status=status.HTTP_404_NOT_FOUND)
        message = (request.data.get('message') or '').strip()
        if not message:
            return Response({'message': ['This field is required.']}, status=status.HTTP_400_BAD_REQUEST)
        item = DoctorChatMessage.objects.create(
            user=request.user,
            doctor=doctor,
            sender='user',
            message=message,
        )
        return Response(DoctorChatMessageSerializer(item).data, status=status.HTTP_201_CREATED)


def _doctor_for_account(user):
    return DoctorProfile.objects.filter(account=user, is_active=True).first()


class DoctorInboxAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        doctor = _doctor_for_account(request.user)
        if not doctor:
            return Response({'detail': 'Doctor account not configured.'}, status=status.HTTP_403_FORBIDDEN)

        grouped = (
            DoctorChatMessage.objects.filter(doctor=doctor)
            .values('user_id')
            .annotate(last_time=Max('created_at'))
            .order_by('-last_time')
        )

        conversations = []
        for row in grouped:
            user_id = row['user_id']
            user = User.objects.filter(id=user_id).first()
            latest = (
                DoctorChatMessage.objects.filter(doctor=doctor, user_id=user_id)
                .order_by('-created_at')
                .first()
            )
            if not user or not latest:
                continue
            display_name = (f'{user.first_name} {user.last_name}').strip() or user.username
            conversations.append(
                {
                    'user_id': user.id,
                    'user_name': display_name,
                    'user_email': user.email,
                    'last_message': latest.message,
                    'last_sender': latest.sender,
                    'last_time': latest.created_at,
                }
            )
        return Response(conversations)


class DoctorUserThreadAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request, user_id: int):
        doctor = _doctor_for_account(request.user)
        if not doctor:
            return Response({'detail': 'Doctor account not configured.'}, status=status.HTTP_403_FORBIDDEN)
        qs = DoctorChatMessage.objects.filter(doctor=doctor, user_id=user_id)
        return Response(DoctorChatMessageSerializer(qs, many=True).data)

    def post(self, request, user_id: int):
        doctor = _doctor_for_account(request.user)
        if not doctor:
            return Response({'detail': 'Doctor account not configured.'}, status=status.HTTP_403_FORBIDDEN)
        patient = User.objects.filter(id=user_id).first()
        if not patient:
            return Response({'detail': 'User not found.'}, status=status.HTTP_404_NOT_FOUND)

        message = (request.data.get('message') or '').strip()
        if not message:
            return Response({'message': ['This field is required.']}, status=status.HTTP_400_BAD_REQUEST)

        item = DoctorChatMessage.objects.create(
            user=patient,
            doctor=doctor,
            sender='doctor',
            message=message,
        )
        return Response(DoctorChatMessageSerializer(item).data, status=status.HTTP_201_CREATED)
