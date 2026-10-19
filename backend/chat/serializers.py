from rest_framework import serializers

from .models import UserMentalState, ChatMessage, ChatSession


class ChatHistoryTurnSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=("user", "assistant"))
    content = serializers.CharField(required=True, allow_blank=False, trim_whitespace=True, max_length=4000)

    def validate_content(self, value: str) -> str:
        text = value.strip()
        if not text:
            raise serializers.ValidationError("History content cannot be empty.")
        return text


class ChatRequestSerializer(serializers.Serializer):
    message = serializers.CharField(required=True, allow_blank=False, trim_whitespace=True)
    session_id = serializers.IntegerField(required=False)
    history = ChatHistoryTurnSerializer(many=True, required=False, default=list)
    behavior_context = serializers.JSONField(required=False, allow_null=True)
    tool = serializers.CharField(required=False, allow_blank=True, trim_whitespace=True, max_length=64)

    def validate_tool(self, value: str) -> str:
        return (value or '').strip()

    def validate_message(self, value: str) -> str:
        text = value.strip()
        if not text:
            raise serializers.ValidationError('Message cannot be empty.')
        if len(text) > 8000:
            raise serializers.ValidationError('Message is too long.')
        return text

    def validate_history(self, value):
        if len(value) > 20:
            raise serializers.ValidationError("History is too long. Max 20 turns.")
        return value


class ChatReplySerializer(serializers.Serializer):
    reply = serializers.CharField()


class UserMentalStateSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserMentalState
        fields = (
            'stress_level',
            'sleep_quality',
            'screen_time',
            'emotion',
            'behavior',
            'last_updated',
        )
        read_only_fields = ('last_updated',)


class ChatHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatMessage
        fields = ('id', 'session', 'message', 'response', 'created_at')


class ChatSessionSerializer(serializers.ModelSerializer):
    turns = serializers.IntegerField(read_only=True)

    class Meta:
        model = ChatSession
        fields = ('id', 'title', 'created_at', 'updated_at', 'turns')


class ChatSessionCreateSerializer(serializers.Serializer):
    title = serializers.CharField(required=False, allow_blank=True, trim_whitespace=True, max_length=120)

    def validate_title(self, value: str) -> str:
        return value.strip() or 'New chat'


class ChatMessageCreateSerializer(serializers.Serializer):
    session_id = serializers.IntegerField(required=False)
    message = serializers.CharField(required=True, allow_blank=False, trim_whitespace=True, max_length=8000)
    response = serializers.CharField(required=True, allow_blank=False, trim_whitespace=True, max_length=12000)


class OpenRouterMessageSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=('system', 'user', 'assistant'))
    content = serializers.CharField(allow_blank=False, trim_whitespace=False, max_length=32000)


class OpenRouterProxySerializer(serializers.Serializer):
    model = serializers.CharField(max_length=200)
    messages = OpenRouterMessageSerializer(many=True)

    def validate_messages(self, value):
        if len(value) > 40:
            raise serializers.ValidationError('Too many messages (max 40).')
        return value
