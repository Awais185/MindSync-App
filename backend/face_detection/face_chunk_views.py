"""POST /api/face/chunk/ — 20s face video → OpenFace → face_analysis (no video stored)."""

from __future__ import annotations

import os
import tempfile

from rest_framework import parsers, permissions, response, status, views

from .identity import face_match_score_from_video_path
from .models import FaceAnalysis
from .openface_pipeline import run_openface_and_analyze


class FaceChunkUploadView(views.APIView):
    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        if 'video' not in request.data:
            return response.Response({'error': 'video required'}, status=status.HTTP_400_BAD_REQUEST)

        source_type = (request.data.get('source_type') or 'video_watch').strip()[:32]
        source_package = (request.data.get('source_package_name') or '')[:200]
        try:
            duration_seconds = int(request.data.get('duration_seconds') or 20)
        except (TypeError, ValueError):
            duration_seconds = 20

        tmp_path = None
        try:
            video_file = request.data['video']
            suffix = '.mp4'
            name = getattr(video_file, 'name', '') or ''
            if name.lower().endswith('.mov'):
                suffix = '.mov'

            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                for chunk in video_file.chunks():
                    tmp.write(chunk)
                tmp_path = tmp.name

            score, matched = face_match_score_from_video_path(request.user, tmp_path)
            if not matched:
                return response.Response(
                    {
                        'error': 'face_identity_mismatch',
                        'match_score': round(score, 4),
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )

            analysis = run_openface_and_analyze(
                input_video_path=tmp_path,
                include_tracked_video=False,
                fast_mode=True,
            )
            scores = analysis.scores if isinstance(analysis.scores, dict) else {}
            active_aus = list(scores.get('active_aus') or [])
            dominant = str(scores.get('dominant_state') or 'neutral')[:32]
            max_score = int(scores.get('max_score') or 0)

            row = FaceAnalysis.objects.create(
                user=request.user,
                source_package=source_package,
                source_type=source_type,
                match_score=score,
                emotion_label=dominant,
                confidence_score=float(max_score) / 100.0,
                action_units=active_aus,
                head_pose={
                    'state_probabilities': scores.get('state_probabilities') or {},
                },
                gaze_data={},
                openface_payload={
                    **scores,
                    'au_summary': analysis.au_summary,
                    'behavioral_insights': analysis.behavioral_insights,
                    'face_visibility_ratio': analysis.face_visibility_ratio,
                },
                stress_score=int(scores.get('stress_score') or 0),
                anxiety_score=int(scores.get('anxiety_score') or 0),
                depression_score=int(scores.get('depression_score') or 0),
            )
            return response.Response(
                {
                    'ok': True,
                    'id': row.id,
                    'match_score': score,
                    'emotion_label': dominant,
                    'action_units': active_aus,
                    'stress_score': row.stress_score,
                    'anxiety_score': row.anxiety_score,
                    'depression_score': row.depression_score,
                },
                status=status.HTTP_201_CREATED,
            )
        except Exception as exc:
            return response.Response(
                {'error': str(exc)[:500]},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
