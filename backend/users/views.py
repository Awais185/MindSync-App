from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.parsers import MultiPartParser, FormParser
from django.utils import timezone
from django.db.models import Sum, Avg
from django.db.models.functions import TruncDate, TruncHour
from datetime import timedelta, datetime
from calendar import monthrange
from tracking.services.behavior_analysis import submit_video_chunk_behavior_analysis
from .serializers import SignupSerializer
from .models import AppUsage, ScreenUsageEvent, VideoChunkAnalysis
from users.app_display_names import display_app_name, rollup_screen_usage_apps
from tracking.models import ScreenTime
class SignupAPIView(APIView):
    parser_classes = (MultiPartParser, FormParser)
    def post(self, request):
        print(f"DEBUG: Received signup data: {request.data}")
        serializer = SignupSerializer(data=request.data)
        if serializer.is_valid():
            serializer.save()
            return Response(
                {"message": "User registered successfully"},
                status=status.HTTP_201_CREATED
            )
        print(f"DEBUG: Signup errors: {serializer.errors}")
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

from .serializers import (
    LoginSerializer,
    GoogleAuthSerializer,
    build_auth_payload,
    doctor_account_flags,
    UserProfileUpdateSerializer,
    PasswordChangeSerializer,
    PasswordResetSerializer,
    AppUsageSerializer,
    TrackUsageSerializer,
)
from rest_framework.permissions import IsAuthenticated, AllowAny

class ProfileUpdateAPIView(APIView):
    permission_classes = (IsAuthenticated,)
    parser_classes = (MultiPartParser, FormParser)

    def put(self, request):
        from .models import UserProfile

        profile, _ = UserProfile.objects.get_or_create(
            user=request.user,
            defaults={"profession": "other", "face_enrolled": False},
        )
        serializer = UserProfileUpdateSerializer(profile, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            # Return updated user data similar to login
            user = request.user
            return Response({
                "username": user.username,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "profession": user.profile.profession,
                "face_enrolled": user.profile.face_enrolled,
                "face_image": user.profile.face_image.url if user.profile.face_image else None
            }, status=status.HTTP_200_OK)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PasswordChangeAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data, context={'request': request})
        if serializer.is_valid():
            serializer.save()
            return Response({'detail': 'Password updated successfully.'}, status=status.HTTP_200_OK)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PasswordResetAPIView(APIView):
    """Forgot password: verify email, username, and full name, then set a new password."""

    permission_classes = (AllowAny,)

    def post(self, request):
        serializer = PasswordResetSerializer(data=request.data)
        if serializer.is_valid():
            serializer.save()
            return Response(
                {'detail': 'Password updated successfully. You can log in with your new password.'},
                status=status.HTTP_200_OK,
            )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class AppUsageAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        """GET usage. Optional query: date=YYYY-MM-DD (single day) or period=day|week|month (default: today)."""
        today = timezone.now().date()
        date_param = request.query_params.get('date')
        period = request.query_params.get('period', 'day')

        if date_param:
            try:
                from datetime import datetime
                target_date = datetime.strptime(date_param, '%Y-%m-%d').date()
            except ValueError:
                target_date = today
        else:
            target_date = today

        if period == 'week':
            start = target_date - timedelta(days=target_date.weekday())
            end = start + timedelta(days=6)
            usage = request.user.app_usage.filter(date__gte=start, date__lte=end)
        elif period == 'month':
            start = target_date.replace(day=1)
            if target_date.month == 12:
                end = target_date.replace(day=31)
            else:
                from calendar import monthrange
                _, last = monthrange(target_date.year, target_date.month)
                end = target_date.replace(day=last)
            usage = request.user.app_usage.filter(date__gte=start, date__lte=end)
        else:
            usage = request.user.app_usage.filter(date=target_date)

        serializer = AppUsageSerializer(usage, many=True)
        return Response(serializer.data)

    def post(self, request):
        app_name = request.data.get('app_name')
        duration = request.data.get('duration_seconds', 0)

        usage, created = AppUsage.objects.get_or_create(
            user=request.user,
            app_name=app_name,
            date=timezone.now().date(),
            defaults={'duration_seconds': int(duration)}
        )

        if not created:
            usage.duration_seconds += int(duration)
            usage.save()

        return Response(AppUsageSerializer(usage).data, status=status.HTTP_200_OK)


class UsageSummaryAPIView(APIView):
    """Secure user-specific screen time summary: daily, weekly, monthly. Authenticated by user token."""
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        """GET summary. Query: period=day|week|month (default day). Returns total_seconds and by_app."""
        from .services.daily_rollup import ensure_past_days_finalized
        ensure_past_days_finalized(request.user)
        
        period = request.query_params.get('period', 'day')
        today = timezone.now().date()

        if period == 'week':
            start = today - timedelta(days=today.weekday())
            end = start + timedelta(days=6)
            qs = ScreenUsageEvent.objects.filter(user=request.user, date__gte=start, date__lte=end)
        elif period == 'month':
            start = today.replace(day=1)
            _, last = monthrange(today.year, today.month)
            end = today.replace(day=last)
            qs = ScreenUsageEvent.objects.filter(user=request.user, date__gte=start, date__lte=end)
        else:
            qs = ScreenUsageEvent.objects.filter(user=request.user, date=today)

        from .app_display_names import rollup_screen_usage_apps
        apps_data = rollup_screen_usage_apps(qs, qs)
        by_app = [{'app_name': x['app_name'], 'duration_seconds': x['usage_time']} for x in apps_data]
        total_seconds = sum(x['duration_seconds'] for x in by_app)

        # Charts from granular events (falls back to empty buckets if no events yet)
        ev_qs = ScreenUsageEvent.objects.filter(user=request.user)
        chart_labels = []
        chart_hours = []
        if period == 'day':
            day_start = timezone.make_aware(datetime.combine(today, datetime.min.time()))
            day_end = day_start + timedelta(days=1)
            hourly = (
                ev_qs.filter(end_time__gte=day_start, end_time__lt=day_end)
                .annotate(h=TruncHour('end_time'))
                .values('h')
                .annotate(total_seconds=Sum('usage_time'))
                .order_by('h')
            )
            hour_map = {row['h']: row['total_seconds'] for row in hourly if row['h']}
            for i in range(24):
                bucket = day_start + timedelta(hours=i)
                chart_labels.append(bucket.strftime('%H:%M'))
                sec = hour_map.get(bucket, 0) or 0
                chart_hours.append(round(sec / 3600, 2))
        elif period == 'week':
            start_d = today - timedelta(days=today.weekday())
            end_d = start_d + timedelta(days=6)
            daily = (
                ev_qs.filter(date__gte=start_d, date__lte=end_d)
                .values('date')
                .annotate(total_seconds=Sum('usage_time'))
                .order_by('date')
            )
            day_map = {row['date']: row['total_seconds'] for row in daily}
            for i in range(7):
                d = start_d + timedelta(days=i)
                chart_labels.append(d.strftime('%a'))
                sec = day_map.get(d, 0) or 0
                chart_hours.append(round(sec / 3600, 2))
        else:
            start_m = today.replace(day=1)
            _, last = monthrange(today.year, today.month)
            end_m = today.replace(day=last)
            daily = (
                ev_qs.filter(date__gte=start_m, date__lte=end_m)
                .values('date')
                .annotate(total_seconds=Sum('usage_time'))
                .order_by('date')
            )
            day_map = {row['date']: row['total_seconds'] for row in daily}
            for i in range((end_m - start_m).days + 1):
                d = start_m + timedelta(days=i)
                chart_labels.append(d.strftime('%d %b'))
                sec = day_map.get(d, 0) or 0
                chart_hours.append(round(sec / 3600, 2))

        return Response({
            'period': period,
            'total_seconds': total_seconds,
            'by_app': by_app,
            'chart': {'labels': chart_labels, 'data': chart_hours},
        })


EXCESSIVE_DAILY_SECONDS = 8 * 3600


class TrackUsageAPIView(APIView):
    """POST granular usage chunks; keeps AppUsage daily rollup in sync."""

    permission_classes = (IsAuthenticated,)

    def post(self, request):
        ser = TrackUsageSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        data = ser.validated_data
        sec = int(data['usage_time'])
        if sec == 0:
            return Response({'ok': True, 'skipped': True})

        app_display = display_app_name(data['package_name'], data['app_name'])

        ScreenUsageEvent.objects.create(
            user=request.user,
            app_name=app_display,
            package_name=data['package_name'],
            usage_time=sec,
            date=data['date'],
            start_time=data['start_time'],
            end_time=data['end_time'],
        )

        usage, _ = AppUsage.objects.get_or_create(
            user=request.user,
            app_name=app_display,
            date=data['date'],
            defaults={'duration_seconds': 0},
        )
        usage.duration_seconds += sec
        usage.save()

        return Response({'ok': True}, status=status.HTTP_201_CREATED)


class DailyUsageAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from .services.daily_rollup import ensure_past_days_finalized
        ensure_past_days_finalized(request.user)
        
        today = timezone.now().date()
        qs = ScreenUsageEvent.objects.filter(user=request.user, date=today)
        total = qs.aggregate(t=Sum('usage_time'))['t'] or 0
        
        # Determine average screen time from the last 7 days (finalized)
        last_7_days = today - timedelta(days=7)
        st_past = ScreenTime.objects.filter(user=request.user, date__gte=last_7_days, date__lt=today, is_finalized=True)
        avg_seconds = st_past.aggregate(a=Avg('total_screen_time'))['a'] or 0

        apps = rollup_screen_usage_apps(qs, qs)
        # Seven bar heights (px-ish, 0–68) for Analytics "Day" view
        tz = timezone.get_current_timezone()
        day_start_local = timezone.make_aware(datetime.combine(today, datetime.min.time()), tz)
        day_end_local = day_start_local + timedelta(days=1)
        hourly = (
            qs.filter(end_time__gte=day_start_local, end_time__lt=day_end_local)
            .annotate(h=TruncHour('end_time'))
            .values('h')
            .annotate(total_seconds=Sum('usage_time'))
        )
        hour_map = {row['h']: row['total_seconds'] for row in hourly if row['h']}
        hour_vals = []
        for i in range(24):
            bucket = day_start_local + timedelta(hours=i)
            hour_vals.append(float(hour_map.get(bucket, 0) or 0))
        mxh = max(hour_vals) if hour_vals else 0.0
        norm = mxh if mxh > 0 else 1.0
        chart_bars_7 = []
        for seg in range(7):
            lo = int(seg * 24 / 7)
            hi = int((seg + 1) * 24 / 7)
            chunk_sum = sum(hour_vals[lo:hi])
            chart_bars_7.append(round((chunk_sum / norm) * 68.0, 2))

        suggestion = None
        if total > EXCESSIVE_DAILY_SECONDS:
            suggestion = (
                'Your screen time today is high. Try a short break, lower brightness, '
                'or schedule app limits in system settings.'
            )
        return Response(
            {
                'date': today.isoformat(),
                'total_seconds': total,
                'avg_seconds': int(avg_seconds),
                'apps': apps,
                'chart_bars_7': chart_bars_7,
                'excessive_usage': total > EXCESSIVE_DAILY_SECONDS,
                'suggestion': suggestion,
            }
        )


class WeeklyUsageAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from .services.daily_rollup import ensure_past_days_finalized
        ensure_past_days_finalized(request.user)
        
        today = timezone.now().date()
        start = today - timedelta(days=today.weekday())
        
        st_past = ScreenTime.objects.filter(user=request.user, date__gte=start, date__lt=today, is_finalized=True)
        day_map = {str(r.date): r.total_screen_time for r in st_past}
        
        today_qs = ScreenUsageEvent.objects.filter(user=request.user, date=today)
        today_total = today_qs.aggregate(t=Sum('usage_time'))['t'] or 0
        day_map[str(today)] = today_total
        
        total = sum(day_map.values())
        labels = []
        data_hours = []
        days_elapsed = (today - start).days + 1
        for i in range(days_elapsed):
            d = start + timedelta(days=i)
            labels.append(d.strftime('%a'))
            sec = day_map.get(str(d), 0)
            data_hours.append(round(sec / 3600, 2))
        while len(labels) < 7:
            labels.append('')
            data_hours.append(0.0)
            
        avg_seconds = total / days_elapsed if days_elapsed > 0 else 0
            
        qs = ScreenUsageEvent.objects.filter(user=request.user, date__gte=start, date__lte=today)
        apps = rollup_screen_usage_apps(qs, qs)
        return Response(
            {
                'range': 'week',
                'total_seconds': total,
                'avg_seconds': int(avg_seconds),
                'chart': {'labels': labels, 'data': data_hours},
                'apps': apps,
            }
        )


class MonthlyUsageAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from .services.daily_rollup import ensure_past_days_finalized
        ensure_past_days_finalized(request.user)
        
        now = timezone.now()
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        today = now.date()
        
        st_past = ScreenTime.objects.filter(user=request.user, date__gte=start.date(), date__lt=today, is_finalized=True)
        by_day = [{'date': r.date, 'day_total': r.total_screen_time} for r in st_past]
        
        today_qs = ScreenUsageEvent.objects.filter(user=request.user, date=today)
        today_total = today_qs.aggregate(t=Sum('usage_time'))['t'] or 0
        by_day.append({'date': today, 'day_total': today_total})
        
        total = sum(d['day_total'] for d in by_day)
        days_elapsed = (today - start.date()).days + 1
        avg_seconds = total / days_elapsed if days_elapsed > 0 else 0
        
        qs = ScreenUsageEvent.objects.filter(user=request.user, date__gte=start.date(), date__lte=today)
        apps = rollup_screen_usage_apps(qs, qs)
        return Response(
            {
                'range': 'month',
                'total_seconds': total,
                'avg_seconds': int(avg_seconds),
                'by_day': by_day,
                'apps': apps,
            }
        )


class LiveUsageAPIView(APIView):
    """Polling: today's total + last event as a lightweight \"current\" hint."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        today = timezone.now().date()
        last = (
            ScreenUsageEvent.objects.filter(user=request.user)
            .order_by('-end_time')
            .first()
        )
        total = (
            ScreenUsageEvent.objects.filter(user=request.user, date=today).aggregate(
                t=Sum('usage_time')
            )['t']
            or 0
        )
        current = None
        if last:
            today_pkg_total = ScreenUsageEvent.objects.filter(
                user=request.user,
                date=today,
                package_name=last.package_name,
            ).aggregate(t=Sum('usage_time'))['t'] or 0
            current = {
                'app_name': display_app_name(last.package_name, last.app_name),
                'package_name': last.package_name,
                'end_time': last.end_time.isoformat(),
                'today_seconds': int(today_pkg_total),
            }
        return Response({'total_seconds': total, 'current_app': current})

class LoginAPIView(APIView):
    def post(self, request):
        print(f"DEBUG: Login attempt for email: {request.data.get('username_or_email')}")
        serializer = LoginSerializer(data=request.data)
        if serializer.is_valid():
            print(f"DEBUG: Login successful for: {request.data.get('username_or_email')}")
            return Response(serializer.validated_data, status=status.HTTP_200_OK)
        
        print(f"DEBUG: Login failed: {serializer.errors}")
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class GoogleAuthAPIView(APIView):
    def post(self, request):
        serializer = GoogleAuthSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            return Response(build_auth_payload(user), status=status.HTTP_200_OK)

        errors = serializer.errors
        code = errors.get('code')
        if isinstance(code, list):
            code = code[0] if code else None
        if code == 'user_not_found':
            return Response(errors, status=status.HTTP_404_NOT_FOUND)
        if code in ('password_account_exists', 'email_already_registered'):
            return Response(errors, status=status.HTTP_409_CONFLICT)
        return Response(errors, status=status.HTTP_400_BAD_REQUEST)


class CurrentUserAPIView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        user = request.user
        profile = getattr(user, 'profile', None)
        is_doctor, is_approved_doctor = doctor_account_flags(user)
        return Response(
            {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "profession": profile.profession if profile else "other",
                "face_enrolled": profile.face_enrolled if profile else False,
                "is_doctor": is_doctor,
                "is_approved_doctor": is_approved_doctor,
                "face_image": (
                    profile.face_image.url
                    if profile and profile.face_image
                    else None
                ),
            },
            status=status.HTTP_200_OK,
        )


class WellnessDashboardAPIView(APIView):
    """Aggregated wellbeing / mental-health metrics (default last 7 days)."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from users.wellbeing import build_wellness_dashboard

        try:
            days = int(request.query_params.get('days') or 7)
        except ValueError:
            days = 7
        days = max(1, min(days, 30))
        return Response(build_wellness_dashboard(request.user, days=days))


class DynamicWeeklySummaryAPIView(APIView):
    """Structured 7-day text + dashboard payload for in-app reports / chat."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from users.services.weekly_report_builder import build_and_save_weekly_report
        from users.wellbeing import build_weekly_report_text

        days = request.query_params.get('days')
        try:
            d = int(days) if days is not None else 7
        except ValueError:
            d = 7
        d = max(1, min(d, 30))
        text_payload = build_weekly_report_text(request.user, days=d)
        if d == 7:
            snapshot = build_and_save_weekly_report(request.user)
            text_payload['seven_day_report'] = snapshot.payload
        return Response(text_payload)


class UserWeeklyReportAPIView(APIView):
    """GET persisted rolling 7-day report JSON for the authenticated user."""

    permission_classes = (IsAuthenticated,)

    def get(self, request):
        from users.mood_views import LiveUserWeeklyReportAPIView

        return LiveUserWeeklyReportAPIView().get(request)


class VideoChunkAnalysisAPIView(APIView):
    """
    Persists OpenRouter vision output for a screen-record chunk (mobile pipeline).
    Body: chunk_id, session_id, script_text(optional), source_package?, created_at (ms)?
    """

    permission_classes = (IsAuthenticated,)

    def post(self, request):
        chunk_id = request.data.get('chunk_id')
        session_id = request.data.get('session_id')
        script_text = request.data.get('script_text')
        if not chunk_id or not session_id:
            return Response(
                {'detail': 'chunk_id and session_id are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        row = VideoChunkAnalysis.objects.create(
            user=request.user,
            chunk_id=str(chunk_id)[:64],
            session_id=str(session_id)[:64],
            script_text=str(script_text or ''),
            source_package=(request.data.get('source_package') or '')[:200] or None,
            client_created_at_ms=request.data.get('created_at'),
        )
        if str(script_text or '').strip():
            # Sync so admin/API see behavior_result immediately (signal also runs on save).
            submit_video_chunk_behavior_analysis(row.id, sync=True)
            row.refresh_from_db()
        return Response(
            {
                'ok': True,
                'id': row.id,
                'behavior_result': row.behavior_result,
                'confidence_score': row.confidence_score,
                'behavior_analyzed_at': (
                    row.behavior_analyzed_at.isoformat() if row.behavior_analyzed_at else None
                ),
                'prediction_error': row.prediction_error or '',
            },
            status=status.HTTP_201_CREATED,
        )
