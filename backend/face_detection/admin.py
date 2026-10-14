from django.contrib import admin
from .models import (
    AppUsage,
    DailyUsage,
    FaceMoodScan,
    FacialExpressionCapture,
    ScreenTimeSession,
)

@admin.register(ScreenTimeSession)
class ScreenTimeSessionAdmin(admin.ModelAdmin):
    list_display = ('user', 'start_time', 'end_time', 'total_duration', 'is_active')
    list_filter = ('is_active', 'user')

@admin.register(AppUsage)
class AppUsageAdmin(admin.ModelAdmin):
    list_display = ('app_name', 'duration', 'session')
    list_filter = ('app_name',)

@admin.register(DailyUsage)
class DailyUsageAdmin(admin.ModelAdmin):
    list_display = ('user', 'date', 'total_screen_time', 'social_media_time')
    list_filter = ('date', 'user')


@admin.register(FacialExpressionCapture)
class FacialExpressionCaptureAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "source_type",
        "status",
        "dominant_state",
        "stress_score",
        "created_at",
        "processed_at",
    )
    list_filter = ("status", "source_type", "dominant_state")
    search_fields = ("user__username", "user__email", "source_app_name", "source_package_name")
    readonly_fields = ("created_at", "updated_at", "processed_at", "video_deleted_at")


@admin.register(FaceMoodScan)
class FaceMoodScanAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "modality", "matched", "source", "created_at")
    list_filter = ("modality", "matched", "source")
    search_fields = ("user__username", "user__email")
