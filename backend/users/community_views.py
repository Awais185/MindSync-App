from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated

from .models import (
    CommunityPost,
    CommunityPostLike,
    CommunityPostComment,
)
from .serializers import (
    CommunityPostSerializer,
    CommunityPostCommentSerializer,
)


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
