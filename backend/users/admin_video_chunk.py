"""Admin helpers for VideoChunkAnalysis behavior display."""

from __future__ import annotations

import json

from django.contrib import admin
from django.contrib.auth.models import User
from django.db.models import Count, Max
from django.template.response import TemplateResponse
from django.urls import reverse
from django.utils.html import escape
from django.utils.safestring import mark_safe

from tracking.services.behavior_analysis import analyze_and_update_video_chunk

from .models import VideoChunkAnalysis


@admin.action(description='Run behavior model on selected (from script_text)')
def admin_run_behavior_model(modeladmin, request, queryset):
    done = 0
    for row in queryset:
        if (row.script_text or '').strip():
            if analyze_and_update_video_chunk(row.id):
                done += 1
    modeladmin.message_user(
        request,
        f'Behavior model finished for {done} of {queryset.count()} selected row(s).',
    )


def format_script_preview(obj: VideoChunkAnalysis, *, max_len: int = 200) -> str:
    text = (obj.script_text or '').strip()
    if not text:
        return '—'
    if len(text) > max_len:
        text = text[:max_len] + '…'
    return text


def format_behavior_details(obj: VideoChunkAnalysis) -> str:
    parts: list[str] = []
    if obj.behavior_result:
        parts.append(f'<strong>Label:</strong> {escape(obj.behavior_result)}')
    if obj.confidence_score is not None:
        parts.append(f'<strong>Confidence:</strong> {obj.confidence_score:.3f}')
    if obj.prediction_error:
        parts.append(f'<strong>Error:</strong> {obj.prediction_error[:500]}')
    outputs = obj.classification_outputs or {}
    top = outputs.get('top_predictions') or []
    if top:
        lines = ', '.join(
            f'{p.get("label")}: {float(p.get("score", 0)):.2f}' for p in top[:5] if isinstance(p, dict)
        )
        parts.append(f'<strong>Top scores:</strong> {lines}')
    if obj.behavior_results and not top:
        parts.append(
            f'<pre style="white-space:pre-wrap;max-height:200px;overflow:auto;">'
            f'{json.dumps(obj.behavior_results, indent=2)[:3000]}</pre>'
        )
    if not parts:
        return '—'
    return mark_safe('<br/>'.join(parts))


def build_video_chunk_user_rows():
    """Users who have at least one VideoChunkAnalysis row, sorted by latest chunk."""
    qs = (
        VideoChunkAnalysis.objects.values('user_id')
        .annotate(
            chunk_count=Count('id'),
            latest_at=Max('created_at'),
        )
        .order_by('-latest_at')
    )
    user_ids = [row['user_id'] for row in qs]
    users = User.objects.in_bulk(user_ids)
    rows = []
    for summary in qs:
        user = users.get(summary['user_id'])
        latest = (
            VideoChunkAnalysis.objects.filter(user_id=summary['user_id'])
            .order_by('-created_at')
            .values('platform', 'behavior_result', 'created_at')
            .first()
        )
        rows.append(
            {
                'user_id': summary['user_id'],
                'username': user.username if user else f'user-{summary["user_id"]}',
                'email': user.email if user else '',
                'chunk_count': summary['chunk_count'],
                'latest_at': summary['latest_at'],
                'latest_platform': (latest or {}).get('platform') or '',
                'latest_behavior': (latest or {}).get('behavior_result') or '',
                'chunks_url': (
                    reverse('admin:users_videochunkanalysis_changelist')
                    + f'?user__id__exact={summary["user_id"]}'
                ),
            }
        )
    return rows


class VideoChunkUserBrowserMixin:
    """Show users first; drill into per-user chunk list sorted newest-first."""

    def changelist_view(self, request, extra_context=None):
        user_filter = request.GET.get('user__id__exact')
        show_all = request.GET.get('all') == '1'
        if not user_filter and not show_all:
            context = {
                **self.admin_site.each_context(request),
                'opts': self.model._meta,
                'title': 'Video chunk analysis — select user',
                'user_rows': build_video_chunk_user_rows(),
            }
            return TemplateResponse(
                request,
                'admin/users/videochunkanalysis/user_browser.html',
                context,
            )
        extra_context = extra_context or {}
        if user_filter:
            user = User.objects.filter(pk=user_filter).first()
            extra_context['title'] = (
                f'Video chunks — {user.username if user else user_filter} (newest first)'
            )
            extra_context['subtitle'] = mark_safe(
                f'<a href="{reverse("admin:users_videochunkanalysis_changelist")}">← Back to all users</a>'
            )
        return super().changelist_view(request, extra_context=extra_context)
