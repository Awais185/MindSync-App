from rest_framework import serializers

from .models import ChildReportedApp


class ParentBlockedAppWriteSerializer(serializers.Serializer):
    package_name = serializers.CharField(max_length=200)
    blocked = serializers.BooleanField()
    app_label = serializers.CharField(max_length=300, required=False, allow_blank=True)


class ChildReportedAppItemSerializer(serializers.Serializer):
    package_name = serializers.CharField(max_length=200)
    app_label = serializers.CharField(max_length=300, required=False, allow_blank=True)


class ChildInstalledAppsReportSerializer(serializers.Serializer):
    apps = ChildReportedAppItemSerializer(many=True)
