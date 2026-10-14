from rest_framework import serializers


class ScreenTimeUpdateSerializer(serializers.Serializer):
    """Increment or set daily totals. Authenticated user owns the row; `user_id` in body is ignored."""

    user_id = serializers.IntegerField(required=False, allow_null=True)
    date = serializers.DateField(required=False)
    # Delta mode (recommended for frequent pings)
    delta_total = serializers.IntegerField(min_value=0, required=False)
    delta_social = serializers.IntegerField(min_value=0, required=False)
    delta_video = serializers.IntegerField(min_value=0, required=False)
    # Absolute mode (replace values for the day)
    total_screen_time = serializers.IntegerField(min_value=0, required=False)
    social_media_time = serializers.IntegerField(min_value=0, required=False)
    video_watch_time = serializers.IntegerField(min_value=0, required=False)
    mode = serializers.ChoiceField(choices=('delta', 'absolute'), default='delta')

    def validate(self, attrs):
        mode = attrs.get('mode', 'delta')
        if mode == 'delta':
            if not any(
                k in attrs and attrs[k] is not None
                for k in ('delta_total', 'delta_social', 'delta_video')
            ):
                raise serializers.ValidationError(
                    'For mode=delta, provide at least one of delta_total, delta_social, delta_video.'
                )
        else:
            if 'total_screen_time' not in attrs:
                raise serializers.ValidationError('For mode=absolute, total_screen_time is required.')
        return attrs


class FaceVerificationEventSerializer(serializers.Serializer):
    event_type = serializers.ChoiceField(choices=('unlock', 'screen_on', 'app_resume'))
    unlock_timestamp = serializers.DateTimeField(required=False, allow_null=True)
    screen_on_timestamp = serializers.DateTimeField(required=False, allow_null=True)
    session_duration_seconds = serializers.IntegerField(min_value=0, required=False, default=0)
    verified_face_match_percent = serializers.FloatField(min_value=0.0, max_value=100.0)
    app_usage_stats = serializers.JSONField(required=False, default=dict)
