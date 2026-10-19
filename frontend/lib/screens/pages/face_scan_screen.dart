import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../services/behavior_analysis_warmup.dart';
import '../../services/plan_access_service.dart';
import '../../config/api_config.dart';
import '../../utils/mental_health_severity.dart';
import '../../widgets/deep_face_analysis_hero.dart';
import 'face_scan_record_screen.dart';

bool _analysisFromOpenFace(String source) {
  final s = source.trim().toLowerCase();
  return s == 'openface' || s.startsWith('openface_');
}

/// OpenFace / behavior analyze responses mix lists and maps depending on API version.
List<String> _jsonStringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  if (value is Map) {
    return value.entries
        .map((e) => '${e.key}: ${e.value}')
        .toList();
  }
  return [value.toString()];
}

List<Map<String, dynamic>> _jsonMapList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

Map<String, dynamic> _jsonStringKeyedMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const {};
}

String _trackedBadgeForAnalysisSource(String source) {
  final s = source.toLowerCase();
  if (s.contains('mediapipe')) return 'FACE MESH TRACKED';
  if (s.contains('openface')) return 'OPENFACE TRACKED';
  if (s.contains('au_video')) return 'AU TRACKED';
  return 'TRACKED VIDEO';
}

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key, this.autoOpenCamera = false});

  /// When true (e.g. from More → Face Scan), opens the device camera immediately.
  final bool autoOpenCamera;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  static const int _maxVideoDurationSeconds = 30;
  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _videoController;
  VideoPlayerController? _sourceVideoController;
  XFile? _selectedVideo;
  String? _analyzedVideoUrl;
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _imageMoodResult;
  Map<String, dynamic>? _videoMoodResult;
  bool _moodLoading = false;
  bool _loading = false;
  String _stage = 'Preparing...';
  double _progress = 0.0;
  Timer? _progressTimer;
  bool _featureAllowed = true;

  @override
  void initState() {
    super.initState();
    unawaited(warmupBehaviorAnalysisModels());
    _ensureAccess();
    if (widget.autoOpenCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _loading || !_featureAllowed) return;
        await _pickRecordedVideo();
      });
    }
  }

  Future<void> _ensureAccess() async {
    final allowed = await PlanAccessService.instance.canAccess(
      'emotion_detection_full',
      forceRefresh: true,
    );
    if (!mounted) return;
    if (!allowed) {
      setState(() => _featureAllowed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade your plan to access this feature.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<http.MultipartFile> _toMultipartFile({
    required String fieldName,
    required XFile file,
  }) async {
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: file.name.isNotEmpty ? file.name : 'upload.mp4',
      );
    }
    final path = file.path;
    final name = file.name.isNotEmpty
        ? file.name
        : (path.toLowerCase().endsWith('.mov') ? 'scan.mov' : 'scan.mp4');
    return http.MultipartFile.fromPath(fieldName, path, filename: name);
  }

  Future<void> _pickRecordedVideo() async {
    if (_loading) return;
    final recorded = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const FaceScanRecordScreen()),
    );
    if (recorded == null || !mounted) return;
    _selectedVideo = recorded;
    setState(() {
      _loading = true;
      _stage = 'Uploading video for analysis…';
      _result = null;
      _analyzedVideoUrl = null;
    });
    _startProgressAnimation();
    unawaited(_initSourceVideoController(recorded));
    await _processVideo(scanType: 'recorded');
  }

  Future<void> _pickUploadedVideo() async {
    if (_loading) return;
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    _selectedVideo = picked;
    setState(() {
      _loading = true;
      _stage = 'Uploading video for analysis…';
      _result = null;
      _analyzedVideoUrl = null;
    });
    _startProgressAnimation();
    unawaited(_initSourceVideoController(picked));
    await _processVideo(scanType: 'uploaded');
  }

  Future<void> _initSourceVideoController(XFile file) async {
    await _sourceVideoController?.dispose();
    try {
      final c = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(file.path))
          : VideoPlayerController.file(File(file.path));
      await c.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _sourceVideoController = c);
    } catch (_) {
      _sourceVideoController = null;
    }
  }

  Future<VideoPlayerController?> _initAnalyzedVideoController(
    String analyzedVideoUrlRaw,
  ) async {
    if (analyzedVideoUrlRaw.isEmpty) return null;
    final resolved = analyzedVideoUrlRaw.startsWith('http')
        ? analyzedVideoUrlRaw
        : '${ApiConfig.baseUrl}$analyzedVideoUrlRaw';
    final uri = Uri.tryParse(resolved);
    if (uri == null) return null;
    try {
      final c = VideoPlayerController.networkUrl(uri);
      await c.initialize().timeout(const Duration(seconds: 20));
      if (!c.value.isInitialized || c.value.hasError) {
        await c.dispose();
        return null;
      }
      c.setLooping(false);
      return c;
    } catch (_) {
      return null;
    }
  }

  void _startProgressAnimation() {
    _progressTimer?.cancel();
    _progress = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 450), (t) {
      if (!mounted || !_loading) return;
      setState(() {
        _progress = (_progress + 0.06).clamp(0.0, 0.93);
      });
    });
  }

  Future<void> _processVideo({required String scanType}) async {
    try {
      final allowed = await PlanAccessService.instance.canAccess(
        'emotion_detection_full',
        forceRefresh: true,
      );
      if (!allowed) {
        _show('Upgrade your plan to access this feature.');
        return;
      }

      final video = _selectedVideo;
      if (video == null) return;
      if (!kIsWeb) {
        try {
          final len = await File(video.path).length();
          if (len < 8_000) {
            _show(
              'Video file is too small. Record at least 2–3 seconds, then try again.',
            );
            return;
          }
        } catch (_) {
          // Server will validate if local check fails.
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) {
        _show('Please login again to continue.');
        return;
      }

      if (mounted) {
        setState(() {
          _loading = true;
          _stage = 'Uploading video...';
          _result = null;
          _analyzedVideoUrl = null;
        });
      }
      _startProgressAnimation();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/face/behavior/analyze/'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['source_type'] = 'random_usage';
      request.fields['scan_type'] = scanType;
      request.fields['fast_mode'] = 'false';
      request.fields['persist'] = 'false';
      request.fields['include_media'] = 'true';
      request.fields['include_deepface_results'] = 'false';
      request.files.add(
        await _toMultipartFile(fieldName: 'video', file: video),
      );

      setState(
        () => _stage = 'Running adult emotion model on your video…',
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 300),
      );
      final resp = await http.Response.fromStream(streamed);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = (body['detail'] ?? body['error'] ?? 'Face analysis failed')
            .toString();
        final hint = (body['hint'] ?? '').toString().trim();
        throw Exception(hint.isEmpty ? msg : '$msg $hint');
      }

      final analyzedVideoUrlRaw = (body['analyzed_video_url'] ?? '').toString();

      await _videoController?.dispose();
      final controller = await _initAnalyzedVideoController(
        analyzedVideoUrlRaw,
      );
      final resolvedVideoUrl = analyzedVideoUrlRaw.isNotEmpty
          ? (analyzedVideoUrlRaw.startsWith('http')
                ? analyzedVideoUrlRaw
                : '${ApiConfig.baseUrl}$analyzedVideoUrlRaw')
          : null;
      if (!mounted) return;
      setState(() {
        _result = body;
        _analyzedVideoUrl = resolvedVideoUrl;
        _videoController = controller;
        _progress = 1.0;
        _stage = 'Completed';
      });
      if (_analyzedVideoUrl != null && _videoController == null) {
        _show(
          'Analysis completed, but this browser cannot play the processed codec.',
        );
      }
      final trackedIncluded = body['tracked_video_included'] == true;
      final processingMs = int.tryParse('${body['processing_time_ms'] ?? 0}') ?? 0;
      if (trackedIncluded && controller != null) {
        unawaited(controller.play());
      }
      if (!trackedIncluded && analyzedVideoUrlRaw.isEmpty) {
        _show(
          'Scores are ready, but the landmark overlay video was not created. '
          'Restart the backend and try a shorter clip (under 20s).',
        );
      } else {
        _show(
          processingMs > 0
              ? 'Deep face analysis complete in ${(processingMs / 1000).toStringAsFixed(1)}s.'
              : 'Deep face analysis complete.',
        );
      }
    } on TimeoutException {
      _show('Analysis timeout. Please try again.');
    } catch (e) {
      _show('Unable to process scan right now. $e');
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _ensureMoodCameraPermission({bool includeMic = false}) async {
    if (kIsWeb) return true;
    var cam = await Permission.camera.status;
    if (!cam.isGranted) {
      cam = await Permission.camera.request();
    }
    if (!cam.isGranted) {
      _show('Camera permission is required for mood capture.');
      return false;
    }
    if (includeMic) {
      var mic = await Permission.microphone.status;
      if (!mic.isGranted) {
        mic = await Permission.microphone.request();
      }
      if (!mic.isGranted) {
        _show('Microphone permission is required for mood video.');
        return false;
      }
    }
    return true;
  }

  Future<void> _captureMoodPhotoFromCamera() async {
    if (!await _ensureMoodCameraPermission()) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    await _runMoodImageWithFile(file);
  }

  Future<void> _captureMoodVideoFromCamera() async {
    if (!await _ensureMoodCameraPermission(includeMic: true)) return;
    final file = await _picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxDuration: const Duration(seconds: 10),
    );
    if (file == null) return;
    await _runMoodVideoWithFile(file);
  }

  Future<void> _runMoodImageWithFile(XFile file) async {
    setState(() {
      _moodLoading = true;
      _stage = 'Analyzing image mood...';
    });
    _startProgressAnimation();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) {
        _show('Sign in required for mood scan.');
        return;
      }
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/face/mood-detect/image/'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await _toMultipartFile(fieldName: 'image', file: file));
      final streamed = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final hint = (data['detail'] ?? data['error'])?.toString();
        _show(hint?.isNotEmpty == true ? hint! : 'Image mood detection failed.');
        return;
      }
      final moodRaw = data['mood'];
      final mood = moodRaw is Map<String, dynamic>
          ? moodRaw
          : (moodRaw is Map ? Map<String, dynamic>.from(moodRaw) : null);
      if (mood == null ||
          (mood.isEmpty && data['error'] == null) ||
          (mood['error'] != null && mood['prediction'] == null && mood['class'] == null)) {
        final hint = (data['detail'] ?? data['message'] ?? mood?['detail'])?.toString();
        _show(
          hint?.isNotEmpty == true
              ? hint!
              : 'Image mood analysis did not return results.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _imageMoodResult = mood;
        _videoMoodResult = null;
        _progress = 1.0;
      });
      final label =
          (mood['prediction'] ?? mood['class'])?.toString();
      final msg = (data['message'] ?? label)?.toString();
      _show(
        msg?.isNotEmpty == true
            ? msg!
            : 'Image mood prediction complete (not saved).',
      );
    } catch (_) {
      _show('Unable to run image mood detection.');
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _moodLoading = false);
      }
    }
  }

  Future<void> _runMoodVideoWithFile(XFile file) async {
    setState(() {
      _moodLoading = true;
      _stage = 'Analyzing video mood...';
    });
    _startProgressAnimation();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) {
        _show('Sign in required for mood scan.');
        return;
      }
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/face/mood-detect/video/'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await _toMultipartFile(fieldName: 'video', file: file));
      final streamed = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _show('Video mood detection failed.');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final mood = data['mood'] as Map<String, dynamic>?;
      if (mood == null || mood.isEmpty) {
        final hint = (data['message'] ?? data['detail'])?.toString();
        _show(
          hint?.isNotEmpty == true
              ? hint!
              : 'Video mood analysis did not return results.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _videoMoodResult = mood;
        _imageMoodResult = null;
        _progress = 1.0;
      });
      final msg = (data['message'] ?? mood['prediction'])?.toString();
      _show(
        msg?.isNotEmpty == true ? msg! : 'Video mood prediction complete.',
      );
    } catch (_) {
      _show('Unable to run video mood detection.');
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _moodLoading = false);
      }
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoController?.dispose();
    _sourceVideoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_featureAllowed) {
      return const Scaffold(
        body: SafeArea(child: SizedBox.shrink()),
      );
    }
    final result = _result;
    final analysisSource =
        (result?['analysis_source'] ?? 'emotion_model_video').toString();
    final modelOnly = result?['model_only_pipeline'] == true ||
        !_analysisFromOpenFace(analysisSource);
    final stress = modelOnly
        ? 0
        : int.tryParse('${result?['stress_score'] ?? 0}') ?? 0;
    final anxiety = modelOnly
        ? 0
        : int.tryParse('${result?['anxiety_score'] ?? 0}') ?? 0;
    final depression = modelOnly
        ? 0
        : int.tryParse('${result?['depression_score'] ?? 0}') ?? 0;
    final dominant = (result?['dominant_state'] ?? 'unknown').toString();
    final severity = modelOnly
        ? 0
        : int.tryParse('${result?['overall_severity_score'] ?? 0}') ?? 0;
    final trackedBadge = _trackedBadgeForAnalysisSource(analysisSource);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4FA),
      appBar: AppBar(
        title: const Text('Deep Face Analysis'),
        backgroundColor: const Color(0xFFF3F4FA),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          const DeepFaceAnalysisIntroCard(),
          const SizedBox(height: 14),
          const DeepFaceMeshSampleImage(),
          const SizedBox(height: 14),
          DeepFaceScanActions(
            maxVideoSeconds: _maxVideoDurationSeconds,
            loading: _loading,
            onRecord: _pickRecordedVideo,
            onUpload: _pickUploadedVideo,
          ),
          if (result != null) ...[
            const SizedBox(height: 14),
            if (_videoController != null &&
                _videoController!.value.isInitialized)
              _TrackedAnalysisVideoCard(
                controller: _videoController!,
                badgeLabel: trackedBadge,
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE2A9)),
                ),
                child: const Text(
                  'Tracked video is not available for this result. Record again with your face centered and good lighting.',
                  style: TextStyle(
                    color: Color(0xFF7A5B00),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            if (result['depression'] is Map && !modelOnly) ...[
              _DepressionResultCard(
                title: modelOnly
                    ? 'Depression screening (OpenFace MLP)'
                    : 'Depression screening (OpenFace AU)',
                payload: Map<String, dynamic>.from(result['depression'] as Map),
              ),
              const SizedBox(height: 14),
            ],
            _AnalysisSessionCard(
              modelOnly: modelOnly,
              emotionLabel:
                  (result['emotion_label'] ?? result['web_style_prediction'] ?? '')
                      .toString(),
              depressionLabel:
                  (result['depression_screening_label'] ?? '').toString(),
              dominant: dominant,
              severity: severity,
              stress: stress,
              anxiety: anxiety,
              depression: depression,
              behavioralInsights: _jsonStringList(result['behavioral_insights']),
              recommendations: _jsonStringList(result['recommendations']),
              aus: _jsonMapList(result['au_summary']),
              activeAus: _jsonStringList(result['active_aus']),
              matchedAusByState: _jsonStringKeyedMap(
                result['matched_aus_by_state'],
              ),
              stateProbabilities: _jsonStringKeyedMap(
                result['state_probabilities'],
              ),
              deepfaceDominant:
                  (result['deepface_dominant_emotion'] ?? '').toString(),
              deepfaceFrames:
                  int.tryParse('${result['deepface_frames_analyzed'] ?? 0}') ??
                      0,
              deepfaceSummary: _jsonStringKeyedMap(
                result['deepface_emotion_summary'],
              ),
              webStylePrediction:
                  (result['web_style_prediction'] ?? '').toString(),
              webStyleConfidence: double.tryParse(
                    '${result['web_style_confidence'] ?? ''}',
                  ) ??
                  0.0,
              analysisSource: analysisSource,
              topStates: _jsonStringList(
                result['score_breakdown']?['dominant_states'] ??
                    result['dominant_states'],
              ).map((e) => e.toUpperCase()).toList(),
            ),
            const SizedBox(height: 18),
          ],
          if (_loading) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5DDFB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress <= 0 ? null : _progress,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8EAF3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mood Detector',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Try anytime with image or video — not tied to face unlock.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6E7381)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ResNet18, EfficientNet & MobileNet · emotion only',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 12),
                _ScanOptionTile(
                  title: 'Mood scan (image)',
                  subtitle: kIsWeb
                      ? 'Take a photo with your webcam'
                      : 'Capture a photo with the front camera',
                  icon: Icons.photo_camera_outlined,
                  onTap: _moodLoading ? null : _captureMoodPhotoFromCamera,
                ),
                const SizedBox(height: 10),
                _ScanOptionTile(
                  title: 'Mood scan (video)',
                  subtitle: kIsWeb
                      ? 'Record a short clip with your webcam'
                      : 'Record a short video with the front camera',
                  icon: Icons.videocam_outlined,
                  onTap: _moodLoading ? null : _captureMoodVideoFromCamera,
                ),
                if (_moodLoading) ...[
                  const SizedBox(height: 14),
                  Text(
                    _stage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (_imageMoodResult != null || _videoMoodResult != null) ...[
                  const SizedBox(height: 14),
                  _MoodDetectorResultCard(
                    modality: _videoMoodResult != null ? 'video' : 'image',
                    payload: Map<String, dynamic>.from(
                      (_videoMoodResult ?? _imageMoodResult)!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOptionTile extends StatelessWidget {
  const _ScanOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E6EE)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6F39E8)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E7381),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _TrackedAnalysisVideoCard extends StatelessWidget {
  const _TrackedAnalysisVideoCard({
    required this.controller,
    required this.badgeLabel,
  });

  final VideoPlayerController controller;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAF3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9FBF6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Color(0xFF0D8E73),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Top banner: scores + active AUs',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7B7F90),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          const SizedBox(height: 8),
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Row(
                children: [
                  IconButton(
                    onPressed: () async {
                      await controller.seekTo(Duration.zero);
                      await controller.play();
                    },
                    icon: const Icon(Icons.replay_rounded),
                  ),
                  IconButton(
                    onPressed: () async {
                      if (controller.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${controller.value.position.inSeconds}s / ${controller.value.duration.inSeconds}s',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E7381),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnalysisSessionCard extends StatelessWidget {
  const _AnalysisSessionCard({
    this.modelOnly = false,
    this.emotionLabel = '',
    this.depressionLabel = '',
    required this.dominant,
    required this.severity,
    required this.stress,
    required this.anxiety,
    required this.depression,
    required this.behavioralInsights,
    required this.recommendations,
    required this.aus,
    required this.activeAus,
    required this.matchedAusByState,
    required this.stateProbabilities,
    required this.deepfaceDominant,
    required this.deepfaceFrames,
    required this.deepfaceSummary,
    required this.webStylePrediction,
    required this.webStyleConfidence,
    required this.analysisSource,
    required this.topStates,
  });

  final bool modelOnly;
  final String emotionLabel;
  final String depressionLabel;
  final String dominant;
  final int severity;
  final int stress;
  final int anxiety;
  final int depression;
  final List<String> behavioralInsights;
  final List<String> recommendations;
  final List<Map<String, dynamic>> aus;
  final List<String> activeAus;
  final Map<String, dynamic> matchedAusByState;
  final Map<String, dynamic> stateProbabilities;
  final String deepfaceDominant;
  final int deepfaceFrames;
  final Map<String, dynamic> deepfaceSummary;
  final String webStylePrediction;
  final double webStyleConfidence;
  final String analysisSource;
  final List<String> topStates;

  @override
  Widget build(BuildContext context) {
    final hasEmotion = emotionLabel.trim().isNotEmpty ||
        webStylePrediction.trim().isNotEmpty ||
        deepfaceDominant.trim().isNotEmpty;
    final emotionDisplay = emotionLabel.trim().isNotEmpty
        ? emotionLabel.trim()
        : (webStylePrediction.trim().isNotEmpty
            ? webStylePrediction.trim()
            : deepfaceDominant.trim());
    final confPct = webStyleConfidence <= 0
        ? null
        : (webStyleConfidence <= 1
            ? (webStyleConfidence * 100).round()
            : webStyleConfidence.round());
    final showOpenFaceAu = !modelOnly && _analysisFromOpenFace(analysisSource);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Video analysis summary',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            modelOnly
                ? 'Mac / cross-platform: adult emotion model on sampled frames. OpenFace depression screening is not available on this device.'
                : 'OpenFace AU pipeline with model labels where available.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6E7381)),
          ),
          const SizedBox(height: 14),
          if (hasEmotion) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEDE9FE), Color(0xFFF5F3FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emotion model',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6D28D9),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    emotionDisplay,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                  if (confPct != null || deepfaceFrames > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (confPct != null) '$confPct% avg confidence',
                        if (deepfaceFrames > 0) '$deepfaceFrames frames sampled',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B5670),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            _UnavailableBanner(
              message:
                  'Emotion model did not return a label. Retry with your face centered and good lighting.',
            ),
          ],
          const SizedBox(height: 12),
          if (depressionLabel.trim().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EEFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4C4F7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.health_and_safety_outlined,
                      color: Color(0xFF5B3E9E), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Depression screening: ${depressionLabel.trim()}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3D2A6B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (modelOnly) ...[
            _UnavailableBanner(
              message:
                  'Depression MLP needs OpenFace AU CSV on the server (Windows). Not available on macOS — emotion results above are still valid.',
            ),
          ],
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BulletCard(title: 'Suggestions', items: recommendations),
          ],
          if (behavioralInsights.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BulletCard(title: 'What we measured', items: behavioralInsights),
          ],
          if (showOpenFaceAu) ...[
            const SizedBox(height: 10),
            Text('Dominant state: ${dominant.toUpperCase()}'),
            const SizedBox(height: 8),
            _ScoreCard(title: 'Stress', value: stress),
            const SizedBox(height: 8),
            _ScoreCard(title: 'Anxiety', value: anxiety),
            const SizedBox(height: 8),
            _ScoreCard(title: 'Depression', value: depression),
            const SizedBox(height: 10),
            _AusCard(aus: aus),
            const SizedBox(height: 10),
            _BulletCard(title: 'Active AUs', items: activeAus),
            const SizedBox(height: 10),
            _AuDiseaseRelationCard(map: matchedAusByState),
            const SizedBox(height: 10),
            _StateProbabilityCard(probabilities: stateProbabilities),
          ],
          if (deepfaceSummary.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DeepFaceSummaryCard(
              dominant: deepfaceDominant,
              framesAnalyzed: deepfaceFrames,
              summary: deepfaceSummary,
            ),
          ],
        ],
      ),
    );
  }
}

class _UnavailableBanner extends StatelessWidget {
  const _UnavailableBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A9)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF7A5B00),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.title,
    required this.value,
  });

  final String title;
  final int value;

  @override
  Widget build(BuildContext context) {
    final safe = value.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: safe / 100,
            color: MentalHealthSeverity.progressBarColor,
            backgroundColor: MentalHealthSeverity.progressBarBackground,
          ),
          const SizedBox(height: 6),
          MentalHealthScoreDisplay(
            percent: safe,
            fontWeight: FontWeight.w600,
            labelFontWeight: FontWeight.w800,
          ),
        ],
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text(
              'No data available',
              style: TextStyle(color: Color(0xFF6E7381)),
            ),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('• $item'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AusCard extends StatelessWidget {
  const _AusCard({required this.aus});
  final List<Map<String, dynamic>> aus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detected Action Unit Summary',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (aus.isEmpty)
            const Text(
              'No AU highlights detected',
              style: TextStyle(color: Color(0xFF6E7381)),
            ),
          ...aus.take(6).map((au) {
            final name = (au['au'] ?? '').toString();
            final intensity = (au['intensity'] ?? au['mean_intensity'] ?? 0)
                .toString();
            final weight = (au['weight'] ?? au['max_intensity'] ?? '')
                .toString();
            final extra = weight.isEmpty ? '' : '  • weight: $weight';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('$name  • intensity: $intensity$extra'),
            );
          }),
        ],
      ),
    );
  }
}

class _DepressionResultCard extends StatelessWidget {
  const _DepressionResultCard({required this.title, required this.payload});

  final String title;
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final label = (payload['predicted_label'] ?? '—').toString();
    final probs = payload['average_class_probabilities_percent'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E6EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Screening class: $label',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2130),
            ),
          ),
          if (probs is Map) ...[
            const SizedBox(height: 8),
            const Text(
              'Class probabilities (%)',
              style: TextStyle(fontSize: 12, color: Color(0xFF6E7381)),
            ),
            ...probs.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${e.key}: ${e.value}'),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Research estimate only — not a clinical diagnosis.',
            style: TextStyle(fontSize: 11, color: Color(0xFF6E7381)),
          ),
        ],
      ),
    );
  }
}

class _MoodDetectorResultCard extends StatelessWidget {
  const _MoodDetectorResultCard({
    required this.modality,
    required this.payload,
  });

  final String modality;
  final Map<String, dynamic> payload;

  static String _pct(dynamic conf) {
    final c = double.tryParse('$conf') ?? 0;
    final pct = c <= 1 ? (c * 100).round() : c.round();
    return '$pct%';
  }

  List<Map<String, dynamic>> _modelRows() {
    final raw = payload['model_predictions'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final votes = payload['architecture_votes'];
    final confs = payload['architecture_confidences'];
    if (votes is! Map) return const [];
    const names = {
      'resnet18': 'ResNet18',
      'efficientnet_b0': 'EfficientNet',
      'mobilenetv3_large': 'MobileNet',
    };
    final order = ['resnet18', 'efficientnet_b0', 'mobilenetv3_large'];
    final rows = <Map<String, dynamic>>[];
    for (final arch in order) {
      if (!votes.containsKey(arch)) continue;
      rows.add({
        'model': names[arch] ?? arch,
        'label': votes[arch],
        'confidence': confs is Map ? confs[arch] : null,
      });
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final prediction = (payload['majority_vote_label'] ??
            payload['prediction'] ??
            payload['class'] ??
            payload['dominant'] ??
            '—')
        .toString();
    final conf = payload['confidence'];
    final isVideo = modality == 'video';
    final frames = payload['frames'];
    final modelRows = _modelRows();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E6EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
                size: 20,
                color: const Color(0xFF6D28D9),
              ),
              const SizedBox(width: 8),
              Text(
                isVideo ? 'Mood detector · video' : 'Mood detector · image',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6D28D9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            prediction,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A2130),
              height: 1.05,
            ),
          ),
          if (conf != null) ...[
            const SizedBox(height: 4),
            Text(
              'Majority vote · ${_pct(conf)} confidence',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6E7381),
              ),
            ),
          ],
          if (modelRows.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Model predictions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF868894),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            ...modelRows.map((row) {
              final name = (row['model'] ?? 'Model').toString();
              final label = (row['label'] ?? '—').toString();
              final c = row['confidence'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2130),
                        ),
                      ),
                    ),
                    Text(
                      c != null ? _pct(c) : '—',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6E7381),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (isVideo && frames is List && frames.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'Sampled frames',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF868894),
              ),
            ),
            const SizedBox(height: 6),
            ...frames.take(8).map((f) {
              if (f is! Map) return const SizedBox.shrink();
              final t = f['time_sec'];
              final lbl = (f['label'] ?? '—').toString();
              final fc = f['confidence'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${t ?? '?'}s · $lbl · ${_pct(fc)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4B5563),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _DeepFaceSummaryCard extends StatelessWidget {
  const _DeepFaceSummaryCard({
    required this.dominant,
    required this.framesAnalyzed,
    required this.summary,
  });

  final String dominant;
  final int framesAnalyzed;
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final entries = summary.entries.toList()
      ..sort(
        (a, b) => (num.tryParse('${b.value}') ?? 0).compareTo(
          num.tryParse('${a.value}') ?? 0,
        ),
      );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DeepFace Emotion Summary (Actual)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Dominant Emotion: ${dominant.isEmpty ? 'N/A' : dominant.toUpperCase()}',
          ),
          Text('Frames analyzed: $framesAnalyzed'),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            const Text(
              'No DeepFace samples available',
              style: TextStyle(color: Color(0xFF6E7381)),
            ),
          ...entries.take(6).map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${e.key}: ${e.value}'),
            );
          }),
        ],
      ),
    );
  }
}

class _AuDiseaseRelationCard extends StatelessWidget {
  const _AuDiseaseRelationCard({required this.map});

  final Map<String, dynamic> map;

  @override
  Widget build(BuildContext context) {
    final states = ['stress', 'anxiety', 'depression'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AU Relation With Conditions',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...states.map((state) {
            final raw = map[state];
            final pairs = <MapEntry<String, double>>[];
            if (raw is Map) {
              for (final e in raw.entries) {
                final v = e.value;
                if (v is num) {
                  pairs.add(MapEntry(e.key.toString(), v.toDouble()));
                }
              }
            } else if (raw is List) {
              for (final item in raw) {
                if (item is! Map) continue;
                final au = (item['au'] ?? '').toString();
                final v = (item['mean_intensity'] ?? item['intensity']) as num?;
                if (au.isNotEmpty && v != null) {
                  pairs.add(MapEntry(au, v.toDouble()));
                }
              }
            }
            pairs.sort((a, b) => b.value.compareTo(a.value));
            final label = state[0].toUpperCase() + state.substring(1);
            final summary = pairs.take(3).map((e) {
              return '${e.key}(${e.value.toStringAsFixed(2)})';
            }).join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '$label: ${summary.isEmpty ? 'No AU data' : summary}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF434859)),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StateProbabilityCard extends StatelessWidget {
  const _StateProbabilityCard({required this.probabilities});

  final Map<String, dynamic> probabilities;

  @override
  Widget build(BuildContext context) {
    final stress = ((probabilities['stress'] as num?) ?? 0).toDouble();
    final anxiety = ((probabilities['anxiety'] as num?) ?? 0).toDouble();
    final depression = ((probabilities['depression'] as num?) ?? 0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Condition Probability (AU-based)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _conditionScoreRow('Stress', stress * 100),
          _conditionScoreRow('Anxiety', anxiety * 100),
          _conditionScoreRow('Depression', depression * 100),
        ],
      ),
    );
  }

  Widget _conditionScoreRow(String name, double percent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$name: ',
            style: const TextStyle(
              color: MentalHealthSeverity.percentTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          MentalHealthScoreDisplay(
            percent: percent,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            labelFontWeight: FontWeight.w800,
          ),
        ],
      ),
    );
  }
}
