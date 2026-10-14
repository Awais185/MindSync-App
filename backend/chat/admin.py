from django.contrib import admin

from .models import UserMentalState, ChatMessage, ChatSession


@admin.register(UserMentalState)
class UserMentalStateAdmin(admin.ModelAdmin):
    list_display = ('user', 'stress_level', 'emotion', 'last_updated')
    search_fields = ('user__username', 'user__email')


@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
    list_display = ('user', 'session', 'created_at')
    search_fields = ('user__username', 'message', 'response')
    readonly_fields = ('created_at',)


@admin.register(ChatSession)
class ChatSessionAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'title', 'updated_at')
    search_fields = ('user__username', 'title')
    readonly_fields = ('created_at', 'updated_at')
