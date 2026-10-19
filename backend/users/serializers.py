import json
import urllib.error
import urllib.request

from rest_framework import serializers
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils.text import slugify
from rest_framework.validators import UniqueValidator
from rest_framework_simplejwt.tokens import RefreshToken
from .models import (
    UserProfile,
    AppUsage,
    CommunityPost,
    CommunityPostLike,
    CommunityPostComment,
    AppBranding,
    SubscriptionPlan,
)


def _normalize_personal_name(value: str) -> str:
    """Collapse internal whitespace and casefold for safe comparison."""
    return ' '.join((value or '').split()).casefold()


def _account_full_name_for_reset(user: User) -> str:
    """How we expect the user to type their name for identity checks."""
    first = (user.first_name or '').strip()
    last = (user.last_name or '').strip()
    if last in ('-', '—', '–', ''):
        return first
    return f'{first} {last}'.strip()


class SignupSerializer(serializers.ModelSerializer):
    profession = serializers.ChoiceField(choices=UserProfile.PROFESSION_CHOICES)
    age_range = serializers.ChoiceField(
        choices=UserProfile.AGE_RANGE_CHOICES,
        required=True,
    )
    face_image = serializers.ImageField(required=False)
    email = serializers.EmailField(
        required=True,
        validators=[UniqueValidator(queryset=User.objects.all(), message="A user with this email already exists.")]
    )

    class Meta:
        model = User
        fields = (
            'username',
            'email',
            'password',
            'first_name',
            'last_name',
            'profession',
            'age_range',
            'face_image',
        )
        extra_kwargs = {
            'password': {'write_only': True},
            'first_name': {'required': True},
            'last_name': {'required': True},
            'email': {'required': True},
        }

    def create(self, validated_data):
        profession = validated_data.pop('profession')
        age_range = validated_data.pop('age_range')
        face_image = validated_data.pop('face_image', None)

        user = User.objects.create_user(**validated_data)

        profile = UserProfile.objects.create(
            user=user,
            profession=profession,
            age_range=age_range,
            face_enrolled=bool(face_image),
            face_image=face_image,
        )
        if face_image:
            try:
                from face_detection.face_verification_service import ensure_profile_embedding

                ensure_profile_embedding(profile)
            except Exception:
                pass

        try:
            from users.services.notification_service import notify_welcome

            notify_welcome(user)
        except Exception:
            pass

        return user

class UserProfileUpdateSerializer(serializers.ModelSerializer):
    first_name = serializers.CharField(source='user.first_name', required=False, allow_blank=True)
    last_name = serializers.CharField(source='user.last_name', required=False, allow_blank=True)
    username = serializers.CharField(source='user.username', required=False)
    email = serializers.EmailField(source='user.email', required=False)
    profession = serializers.ChoiceField(choices=UserProfile.PROFESSION_CHOICES, required=False)
    face_image = serializers.ImageField(required=False)

    class Meta:
        model = UserProfile
        fields = ('first_name', 'last_name', 'username', 'email', 'profession', 'face_image')

    def validate_username(self, value):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return value
        if User.objects.filter(username=value).exclude(pk=request.user.pk).exists():
            raise serializers.ValidationError('This username is already taken.')
        return value

    def update(self, instance, validated_data):
        user_data = validated_data.pop('user', {})
        first_name = user_data.get('first_name')
        last_name = user_data.get('last_name')
        username = user_data.get('username')
        email = user_data.get('email')

        if first_name is not None:
            instance.user.first_name = first_name
        if last_name is not None:
            instance.user.last_name = last_name
        if username:
            instance.user.username = username
        if email:
            instance.user.email = email
        instance.user.save()

        if 'profession' in validated_data:
            instance.profession = validated_data['profession']
        face_image = validated_data.get('face_image')
        if face_image:
            instance.face_image = face_image
            instance.face_enrolled = True
            instance.face_embedding = []

        instance.save()
        if face_image:
            try:
                from face_detection.face_verification_service import ensure_profile_embedding

                ensure_profile_embedding(instance)
            except Exception:
                pass
        return instance


class PasswordChangeSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate(self, attrs):
        request = self.context.get('request')
        user = request.user if request and request.user.is_authenticated else None
        if not user:
            raise serializers.ValidationError('Not authenticated.')
        if not user.check_password(attrs['current_password']):
            raise serializers.ValidationError({'current_password': ['Current password is incorrect.']})
        return attrs

    def save(self):
        user = self.context['request'].user
        user.set_password(self.validated_data['new_password'])
        user.save()
        try:
            from users.services.notification_service import notify_password_changed

            notify_password_changed(user)
        except Exception:
            pass
        return user


class PasswordResetSerializer(serializers.Serializer):
    """
    Unauthenticated reset: email + username + full name must all match the same
    account before the password is changed.
    """

    email = serializers.EmailField()
    username = serializers.CharField(max_length=150)
    full_name = serializers.CharField(max_length=300)
    new_password = serializers.CharField(write_only=True, min_length=8)
    confirm_password = serializers.CharField(write_only=True, min_length=8)

    def validate(self, attrs):
        if attrs['new_password'] != attrs['confirm_password']:
            raise serializers.ValidationError(
                {'confirm_password': ['Passwords do not match.']}
            )

        email = attrs['email'].strip().lower()
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            raise serializers.ValidationError(
                {'email': ['No account found with this email.']}
            )

        submitted_username = attrs['username'].strip()
        if user.username.casefold() != submitted_username.casefold():
            raise serializers.ValidationError(
                {'username': ['Username does not match this account.']}
            )

        expected = _account_full_name_for_reset(user)
        if _normalize_personal_name(attrs['full_name']) != _normalize_personal_name(
            expected
        ):
            raise serializers.ValidationError(
                {
                    'full_name': [
                        'Name does not match this account. Use the same first and last name you registered with.'
                    ]
                }
            )

        try:
            validate_password(attrs['new_password'], user=user)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({'new_password': list(exc.messages)})

        attrs['user'] = user
        return attrs

    def save(self):
        user = self.validated_data['user']
        try:
            from users.services.notification_service import (
                notify_password_changed,
                notify_password_reset_requested,
            )

            notify_password_reset_requested(user)
        except Exception:
            pass
        user.set_password(self.validated_data['new_password'])
        user.save()
        try:
            from users.services.notification_service import notify_password_changed

            notify_password_changed(user)
        except Exception:
            pass
        return user


class AppUsageSerializer(serializers.ModelSerializer):
    class Meta:
        model = AppUsage
        fields = ('app_name', 'duration_seconds', 'date')


class TrackUsageSerializer(serializers.Serializer):
    app_name = serializers.CharField(max_length=200)
    package_name = serializers.CharField(max_length=200)
    usage_time = serializers.IntegerField(min_value=0)
    date = serializers.DateField()
    start_time = serializers.DateTimeField()
    end_time = serializers.DateTimeField()

    def validate(self, attrs):
        if attrs['end_time'] < attrs['start_time']:
            raise serializers.ValidationError('end_time must be on or after start_time')
        return attrs


def doctor_account_flags(user: User) -> tuple[bool, bool]:
    dp = getattr(user, 'doctor_profile', None)
    if dp is None:
        return False, False
    approved = bool(getattr(dp, 'is_active', False))
    return True, approved


def build_auth_payload(user: User):
    refresh = RefreshToken.for_user(user)
    is_doctor, is_approved_doctor = doctor_account_flags(user)

    profession = "other"
    face_enrolled = False
    face_image = None
    google_auth = False
    try:
        if hasattr(user, 'profile'):
            profession = user.profile.profession
            face_enrolled = user.profile.face_enrolled
            google_auth = bool(user.profile.google_auth)
            if user.profile.face_image:
                face_image = user.profile.face_image.url
    except Exception:
        pass

    return {
        "refresh": str(refresh),
        "access": str(refresh.access_token),
        "user": {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "profession": profession,
            "face_enrolled": face_enrolled,
            "face_image": face_image,
            "is_doctor": is_doctor,
            "is_approved_doctor": is_approved_doctor,
            "google_auth": google_auth,
        }
    }


def _profile_is_google_user(user: User) -> bool:
    profile = getattr(user, 'profile', None)
    if profile is not None and profile.google_auth:
        return True
    return not user.has_usable_password()


def _google_profile_payload(profile: dict) -> dict:
    email = (profile.get('email') or '').strip().lower()
    first_name = (profile.get('given_name') or '').strip()
    last_name = (profile.get('family_name') or '').strip()
    display_name = (profile.get('name') or '').strip()
    if not first_name and display_name:
        parts = display_name.split()
        first_name = parts[0]
        if len(parts) > 1 and not last_name:
            last_name = ' '.join(parts[1:])
    return {
        'email': email,
        'display_name': display_name or first_name or email.split('@')[0],
        'first_name': first_name,
        'last_name': last_name,
        'photo_url': (profile.get('picture') or '').strip() or None,
        'uid': (profile.get('sub') or '').strip(),
    }


def _fetch_google_userinfo(access_token: str) -> dict:
    req = urllib.request.Request(
        'https://www.googleapis.com/oauth2/v3/userinfo',
        headers={'Authorization': f'Bearer {access_token}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read().decode('utf-8')
    except urllib.error.HTTPError:
        raise serializers.ValidationError({'access_token': ['Google authentication failed.']})
    except urllib.error.URLError:
        raise serializers.ValidationError({'access_token': ['Unable to reach Google right now.']})

    try:
        profile = json.loads(raw)
    except json.JSONDecodeError:
        raise serializers.ValidationError({'access_token': ['Invalid Google response.']})

    email = (profile.get('email') or '').strip().lower()
    if not email:
        raise serializers.ValidationError({'access_token': ['Google account email is unavailable.']})
    if not profile.get('email_verified', False):
        raise serializers.ValidationError({'access_token': ['Google email is not verified.']})
    return profile


def _unique_username_from_email(email: str, fallback_seed: str = 'google-user') -> str:
    local_part = (email or '').split('@')[0].strip()
    base = slugify(local_part) or slugify(fallback_seed) or 'google-user'
    username = base[:150]
    counter = 1
    while User.objects.filter(username=username).exists():
        suffix = f'-{counter}'
        username = f'{base[: max(1, 150 - len(suffix))]}{suffix}'
        counter += 1
    return username

class LoginSerializer(serializers.Serializer):
    username_or_email = serializers.CharField()
    password = serializers.CharField()

    def validate(self, data):
        username_or_email = (data.get('username_or_email') or '').strip()
        password = data.get('password')

        if not username_or_email or not password:
            raise serializers.ValidationError("Invalid credentials")

        # Search Django SQL database (auth_user) by email or username (case-insensitive)
        user = (
            User.objects.filter(email__iexact=username_or_email).first()
            or User.objects.filter(username__iexact=username_or_email).first()
        )

        if not user:
            raise serializers.ValidationError("Invalid credentials")

        user = authenticate(username=user.username, password=password)
        if not user:
            raise serializers.ValidationError("Invalid credentials")

        return build_auth_payload(user)


class GoogleAuthSerializer(serializers.Serializer):
    access_token = serializers.CharField()
    flow = serializers.ChoiceField(choices=('login', 'signup'), default='login')

    def validate(self, attrs):
        access_token = attrs['access_token'].strip()
        if not access_token:
            raise serializers.ValidationError({'access_token': ['This field is required.']})

        profile = _fetch_google_userinfo(access_token)
        google_profile = _google_profile_payload(profile)
        email = google_profile['email']
        first_name = google_profile['first_name']
        last_name = google_profile['last_name']
        flow = attrs.get('flow') or 'login'

        user = User.objects.filter(email__iexact=email).first()

        if flow == 'login':
            if user is None:
                raise serializers.ValidationError({
                    'code': 'user_not_found',
                    'message': 'No MindSync account exists for this Google email.',
                    'google_profile': google_profile,
                })
            if user.has_usable_password() and not _profile_is_google_user(user):
                raise serializers.ValidationError({
                    'code': 'password_account_exists',
                    'message': (
                        'An account with this email already exists. '
                        'Please log in with your email and password.'
                    ),
                })
        else:
            if user is not None:
                if user.has_usable_password() and not _profile_is_google_user(user):
                    raise serializers.ValidationError({
                        'code': 'email_already_registered',
                        'message': (
                            'An account with this email already exists. '
                            'Log in with your password or use a different Google account.'
                        ),
                    })

        google_user_created = False
        if user is None:
            user = User.objects.create(
                username=_unique_username_from_email(email, profile.get('sub') or 'google-user'),
                email=email,
                first_name=first_name or 'Google',
                last_name=last_name,
            )
            user.set_unusable_password()
            user.save()
            UserProfile.objects.create(
                user=user,
                profession='other',
                face_enrolled=False,
                google_auth=True,
            )
            google_user_created = True
        else:
            if not user.first_name and first_name:
                user.first_name = first_name
            if not user.last_name and last_name:
                user.last_name = last_name
            if not user.email:
                user.email = email
            if user.pk:
                user.save(update_fields=['first_name', 'last_name', 'email'])

            profile_obj, _created = UserProfile.objects.get_or_create(
                user=user,
                defaults={
                    'profession': 'other',
                    'face_enrolled': False,
                    'google_auth': True,
                },
            )
            if not profile_obj.google_auth:
                profile_obj.google_auth = True
                profile_obj.save(update_fields=['google_auth'])

        attrs['user'] = user
        attrs['google_user_created'] = google_user_created
        return attrs

    def create(self, validated_data):
        user = validated_data['user']
        if validated_data.get('google_user_created'):
            try:
                from users.services.notification_service import notify_welcome

                notify_welcome(user)
            except Exception:
                pass
        return user


class CommunityPostSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    comments_count = serializers.SerializerMethodField()
    liked_by_me = serializers.SerializerMethodField()

    class Meta:
        model = CommunityPost
        fields = (
            'id',
            'content',
            'category',
            'created_at',
            'user_name',
            'likes_count',
            'comments_count',
            'liked_by_me',
        )
        read_only_fields = (
            'id',
            'created_at',
            'user_name',
            'likes_count',
            'comments_count',
            'liked_by_me',
        )

    def get_user_name(self, obj):
        first = obj.user.first_name.strip()
        last = obj.user.last_name.strip()
        full = f'{first} {last}'.strip()
        return full or obj.user.username

    def get_likes_count(self, obj):
        return CommunityPostLike.objects.filter(post=obj).count()

    def get_comments_count(self, obj):
        return CommunityPostComment.objects.filter(post=obj).count()

    def get_liked_by_me(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return CommunityPostLike.objects.filter(post=obj, user=request.user).exists()


class CommunityPostCommentSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()

    class Meta:
        model = CommunityPostComment
        fields = ('id', 'content', 'created_at', 'user_name')
        read_only_fields = ('id', 'created_at', 'user_name')

    def get_user_name(self, obj):
        first = obj.user.first_name.strip()
        last = obj.user.last_name.strip()
        full = f'{first} {last}'.strip()
        return full or obj.user.username


class AppBrandingSerializer(serializers.ModelSerializer):
    logo_url = serializers.SerializerMethodField()

    class Meta:
        model = AppBranding
        fields = ('app_name', 'welcome_tagline', 'logo_url', 'updated_at')

    def get_logo_url(self, obj):
        request = self.context.get('request')
        if not obj.logo:
            return ''
        url = obj.logo.url
        if request is None:
            return url
        return request.build_absolute_uri(url)


class SubscriptionPlanSerializer(serializers.ModelSerializer):
    price_monthly = serializers.SerializerMethodField()

    class Meta:
        model = SubscriptionPlan
        fields = (
            'slug',
            'title',
            'subtitle',
            'description',
            'price_monthly',
            'features',
            'button_label',
            'badge',
            'is_featured',
            'sort_order',
        )

    def get_price_monthly(self, obj):
        return float(obj.price_monthly)
