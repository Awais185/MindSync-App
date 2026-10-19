"""OpenAPI (Swagger) request/response schemas for auth endpoints."""

from drf_spectacular.utils import OpenApiExample, extend_schema, inline_serializer
from rest_framework import serializers

from .serializers import GoogleAuthSerializer, LoginSerializer, PasswordResetSerializer, SignupSerializer


class AuthUserResponseSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    username = serializers.CharField()
    email = serializers.EmailField()
    first_name = serializers.CharField()
    last_name = serializers.CharField()
    profession = serializers.CharField()
    face_enrolled = serializers.BooleanField()
    face_image = serializers.CharField(allow_null=True)
    is_doctor = serializers.BooleanField()
    is_approved_doctor = serializers.BooleanField()
    google_auth = serializers.BooleanField()


class AuthTokenResponseSerializer(serializers.Serializer):
    refresh = serializers.CharField(help_text='JWT refresh token')
    access = serializers.CharField(help_text='JWT access token — use in Swagger Authorize as Bearer <access>')
    user = AuthUserResponseSerializer()


class TokenRefreshRequestSerializer(serializers.Serializer):
    refresh = serializers.CharField(help_text='Refresh token from login response')


class TokenRefreshResponseSerializer(serializers.Serializer):
    access = serializers.CharField()


LOGIN_EXAMPLE = OpenApiExample(
    'Email login',
    value={
        'username_or_email': 'user@example.com',
        'password': 'YourSecurePassword123',
    },
    request_only=True,
)

SIGNUP_JSON_EXAMPLE = OpenApiExample(
    'JSON signup (no face image)',
    value={
        'username': 'johndoe',
        'email': 'john@example.com',
        'password': 'YourSecurePassword123',
        'first_name': 'John',
        'last_name': 'Doe',
        'profession': 'student',
        'age_range': '16 - 30 years',
    },
    request_only=True,
)

login_schema = extend_schema(
    tags=['Authentication'],
    summary='Login (email or username + password)',
    description=(
        'Returns JWT `access` and `refresh` tokens. '
        'In Swagger UI: **Authorize** → paste `Bearer <access>` (include the word Bearer).'
    ),
    request=LoginSerializer,
    examples=[LOGIN_EXAMPLE],
    responses={200: AuthTokenResponseSerializer},
)

signup_schema = extend_schema(
    tags=['Authentication'],
    summary='Register a new account',
    description=(
        'Send **application/json** (Swagger) or **multipart/form-data** (mobile app with optional `face_image`).'
    ),
    request=SignupSerializer,
    examples=[SIGNUP_JSON_EXAMPLE],
    responses={
        201: inline_serializer(
            name='SignupResponse',
            fields={'message': serializers.CharField()},
        ),
    },
)

google_auth_schema = extend_schema(
    tags=['Authentication'],
    summary='Google OAuth login or signup',
    request=GoogleAuthSerializer,
    examples=[
        OpenApiExample(
            'Google login',
            value={'access_token': '<google-access-token>', 'flow': 'login'},
            request_only=True,
        ),
    ],
    responses={200: AuthTokenResponseSerializer},
)

password_reset_schema = extend_schema(
    tags=['Authentication'],
    summary='Reset password (forgot password)',
    request=PasswordResetSerializer,
)

token_refresh_schema = extend_schema(
    tags=['Authentication'],
    summary='Refresh JWT access token',
    request=TokenRefreshRequestSerializer,
    examples=[
        OpenApiExample(
            'Refresh',
            value={'refresh': '<paste refresh token from login>'},
            request_only=True,
        ),
    ],
    responses={200: TokenRefreshResponseSerializer},
)
