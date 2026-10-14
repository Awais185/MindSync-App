import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../services/plan_access_service.dart';
import '../../services/screen_time_service.dart';
import '../../config/api_config.dart';
import '../../utils/mental_health_severity.dart';
import '../../widgets/permission_banner.dart';
import 'face_scan_record_screen.dart';

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

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key, this.autoOpenCamera = false});

  /// When true (e.g. from More → Face Scan), opens the device camera immediately.
  final bool autoOpenCamera;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  static const int _maxVideoDurationSeconds = 30;
  static const String _moodCooldownUntilKey = 'face_mood_cooldown_until_ms';
  static const String _moodRetryAfterKey = 'face_mood_retry_after_ms';
  static const MethodChannel _trackerChannel = MethodChannel('mindsync/screen_time');
  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _videoController;
  VideoPlayerController? _sourceVideoController;
  XFile? _selectedVideo;
  String? _analyzedVideoUrl;
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _imageMoodResult;
  Map<String, dynamic>? _videoMoodResult;
  bool _loading = false;
  String _stage = 'Preparing...';
  double _progress = 0.0;
  Timer? _progressTimer;
  AnalysisMode _analysisMode =
      kIsWeb ? AnalysisMode.fast : AnalysisMode.accurate;
  bool _featureAllowed = true;

  @override
  void initState() {
    super.initState();
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
    final recorded = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const FaceScanRecordScreen()),
    );
    if (recorded == null) return;
    _selectedVideo = recorded;
    await _initSourceVideoController(recorded);
    await _processVideo(scanType: 'recorded');
  }

  Future<void> _pickUploadedVideo() async {
    if (_loading) return;
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    _selectedVideo = picked;
    await _initSourceVideoController(picked);
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
        if (len < 12_000) {
          _show(
            'Video file is too small. Record again and wait for preview playback.',
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

    setState(() {
      _loading = true;
      _stage = 'Uploading video...';
      _result = null;
      _analyzedVideoUrl = null;
    });
    _startProgressAnimation();

    try {
      final selectedFast = _analysisMode == AnalysisMode.fast;

      Future<Map<String, dynamic>> runAnalyze({
        required bool fastMode,
      }) async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiConfig.baseUrl}/api/face/behavior/analyze/'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['source_type'] = 'random_usage';
        request.fields['scan_type'] = scanType;
        request.fields['fast_mode'] = fastMode ? 'true' : 'false';
        request.fields['include_media'] = 'true';
        request.fields['include_deepface_results'] = 'true';
        request.files.add(
          await _toMultipartFile(fieldName: 'video', file: video),
        );

        final streamed = await request.send().timeout(
          Duration(minutes: fastMode ? 6 : 8),
        );
        final resp = await http.Response.fromStream(streamed);
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          final msg = (body['detail'] ?? body['error'] ?? 'Face analysis failed')
              .toString();
          final hint = (body['hint'] ?? '').toString().trim();
          throw Exception(hint.isEmpty ? msg : '$msg $hint');
        }
        return body;
      }

      setState(
        () => _stage = selectedFast
            ? 'Running fast OpenFace analysis with tracked video...'
            : 'Running high-accuracy analysis...',
      );
      var body = await runAnalyze(fastMode: selectedFast);
      var analyzedVideoUrlRaw = (body['analyzed_video_url'] ?? '').toString();

      // If tracked output is missing, auto-retry once in high-accuracy mode (camera + upload).
      final trackedIncluded = body['tracked_video_included'] == true;
      if ((analyzedVideoUrlRaw.isEmpty || !trackedIncluded) && selectedFast) {
        if (mounted) {
          setState(() {
            _stage = 'Tracked video missing, retrying in high-accuracy mode...';
          });
        }
        body = await runAnalyze(fastMode: false);
        analyzedVideoUrlRaw = (body['analyzed_video_url'] ?? '').toString();
      }

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
      final processingMs = int.tryParse('${body['processing_time_ms'] ?? 0}') ?? 0;
      _show(
        processingMs > 0
            ? 'Deep face analysis complete in ${(processingMs / 1000).toStringAsFixed(1)}s.'
            : 'Deep face analysis complete.',
      );
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
    // Web: browser prompts for camera/mic; permission_handler is not used on web.
    if (kIsWeb) return true;
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      _show('Camera permission is required for mood capture.');
      return false;
    }
    if (includeMic) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _show('Microphone permission is required for mood video.');
        return false;
      }
    }
    return true;
  }

  Future<bool> _isMoodCapturePaused() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_moodCooldownUntilKey) ?? 0;
    if (until <= 0) return false;
    if (DateTime.now().millisecondsSinceEpoch < until) {
      final mins = ((until - DateTime.now().millisecondsSinceEpoch) / 60000).ceil();
      _show(
        'Mood capture is paused for ${mins.clamp(1, 5)} min after your last match (saves data).',
      );
      return true;
    }
    return false;
  }

  Future<void> _applyMoodCapturePause() async {
    final until = DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_moodCooldownUntilKey, until);
    await prefs.remove(_moodRetryAfterKey);
    if (!kIsWeb) {
      try {
        await _trackerChannel.invokeMethod<void>('applyFaceMatchPause');
      } catch (_) {}
    }
  }

  Future<void> _scheduleMoodRetryAfterFail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _moodRetryAfterKey,
      DateTime.now().millisecondsSinceEpoch + 60 * 1000,
    );
  }

  Future<bool> _canRetryMoodAfterFail() async {
    final prefs = await SharedPreferences.getInstance();
    final after = prefs.getInt(_moodRetryAfterKey) ?? 0;
    if (after <= 0) return true;
    if (DateTime.now().millisecondsSinceEpoch >= after) return true;
    final secs = ((after - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    _show('Face did not match — try again in ${secs.clamp(1, 60)} seconds.');
    return false;
  }

  Future<void> _captureMoodPhotoFromCamera() async {
    if (await _isMoodCapturePaused()) return;
    if (!await _canRetryMoodAfterFail()) return;
    if (!await _ensureMoodCameraPermission()) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    await _runMoodImageWithFile(file);
  }

  Future<void> _captureMoodVideoFromCamera() async {
    if (await _isMoodCapturePaused()) return;
    if (!await _canRetryMoodAfterFail()) return;
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
      _loading = true;
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _show('Image mood detection failed.');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final mood = data['mood'] as Map<String, dynamic>?;
      if (mood == null || mood.isEmpty) {
        final hint = (data['message'] ?? data['detail'])?.toString();
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
        _progress = 1.0;
      });
      final msg = (data['message'] ?? mood['prediction'])?.toString();
      _show(
        msg?.isNotEmpty == true ? msg! : 'Image mood prediction complete.',
      );
    } catch (_) {
      _show('Unable to run image mood detection.');
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runMoodVideoWithFile(XFile file) async {
    setState(() {
      _loading = true;
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
        setState(() => _loading = false);
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
    final stress = int.tryParse('${result?['stress_score'] ?? 0}') ?? 0;
    final anxiety = int.tryParse('${result?['anxiety_score'] ?? 0}') ?? 0;
    final depression = int.tryParse('${result?['depression_score'] ?? 0}') ?? 0;
    final dominant = (result?['dominant_state'] ?? 'unknown').toString();
    final severity =
        int.tryParse('${result?['overall_severity_score'] ?? 0}') ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4FA),
      appBar: AppBar(
        title: const Text('Deep Face Analysis'),
        backgroundColor: const Color(0xFFF3F4FA),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6F39E8), Color(0xFF4B2AAD)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF6F39E8).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deep Face Analysis',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'OpenFace tracked video + stress, anxiety, depression insights',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE8DDFF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ScanOptionTile(
            title: 'Record From Camera',
            subtitle: 'Record face video with timer (max ${_maxVideoDurationSeconds}s)',
            icon: Icons.videocam_rounded,
            onTap: _loading ? null : _pickRecordedVideo,
          ),
          const SizedBox(height: 10),
          _ScanOptionTile(
            title: 'Upload',
            subtitle: 'Choose a video from gallery or storage',
            icon: Icons.upload_file_rounded,
            onTap: _loading ? null : _pickUploadedVideo,
          ),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, bool>>(
            future: Future.wait([
              Permission.camera.isGranted,
              Permission.microphone.isGranted,
              ScreenTimeService.instance.hasScreenCapturePermission(),
            ]).then((list) => {
                  'cam': list[0],
                  'mic': list[1],
                  'screen': list[2],
                }),
            builder: (context, snap) {
              final perms = snap.data ?? {'cam': true, 'mic': true, 'screen': true};
              final missing = <Widget>[];

              if (perms['cam'] == false) {
                missing.add(PermissionBanner(
                  title: 'Camera Required',
                  description: 'Camera is needed to record a face scan.',
                  icon: Icons.camera_alt,
                  onAllow: () async {
                    await Permission.camera.request();
                    setState(() {});
                  },
                ));
              }
              if (perms['mic'] == false) {
                missing.add(PermissionBanner(
                  title: 'Microphone Required',
                  description: 'Microphone is needed for video mood recording.',
                  icon: Icons.mic,
                  onAllow: () async {
                    await Permission.microphone.request();
                    setState(() {});
                  },
                ));
              }
              if (perms['screen'] == false) {
                missing.add(PermissionBanner(
                  title: 'Screen Capture Required',
                  description: 'Screen capture enables background emotion tracking.',
                  icon: Icons.screen_share,
                  onAllow: () async {
                    await ScreenTimeService.instance.ensureScreenCapturePermission();
                    setState(() {});
                  },
                ));
              }

              if (missing.isEmpty) return const SizedBox.shrink();
              return Column(
                children: missing.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: e,
                )).toList(),
              );
            },
          ),
          _AnalysisModeToggle(
            mode: _analysisMode,
            onChanged: _loading ? null : (mode) => setState(() => _analysisMode = mode),
          ),
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
          if (_videoController != null &&
              _videoController!.value.isInitialized) ...[
            const SizedBox(height: 18),
            Container(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9FBF6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'OPENFACE TRACKED',
                          style: TextStyle(
                            color: Color(0xFF0D8E73),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Landmarks + AU',
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
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  VideoProgressIndicator(
                    _videoController!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () async {
                          await _videoController!.seekTo(Duration.zero);
                          await _videoController!.play();
                          setState(() {});
                        },
                        icon: const Icon(Icons.replay_rounded),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (_videoController!.value.isPlaying) {
                            await _videoController!.pause();
                          } else {
                            await _videoController!.play();
                          }
                          setState(() {});
                        },
                        icon: Icon(
                          _videoController!.value.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_videoController!.value.position.inSeconds}s / ${_videoController!.value.duration.inSeconds}s',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E7381),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (result != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE2A9)),
              ),
              child: const Text(
                'Analyzed tracked video is not available for this result. Try High Accuracy mode for richer output.',
                style: TextStyle(
                  color: Color(0xFF7A5B00),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 18),
            _AnalysisSessionCard(
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
                  int.tryParse('${result['deepface_frames_analyzed'] ?? 0}') ?? 0,
              deepfaceSummary: _jsonStringKeyedMap(
                result['deepface_emotion_summary'],
              ),
              webStylePrediction:
                  (result['web_style_prediction'] ?? '').toString(),
              webStyleConfidence: double.tryParse(
                    '${result['web_style_confidence'] ?? ''}',
                  ) ??
                  0.0,
              analysisSource: (result['analysis_source'] ?? 'openface').toString(),
              topStates: _jsonStringList(
                result['score_breakdown']?['dominant_states'] ??
                    result['dominant_states'],
              ).map((e) => e.toUpperCase()).toList(),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Mood Detector',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Predict mood from any face — no login identity check on this screen',
            style: TextStyle(fontSize: 12, color: Color(0xFF6E7381)),
          ),
          const SizedBox(height: 10),
          _ScanOptionTile(
            title: 'Mood scan (image)',
            subtitle: kIsWeb
                ? 'Take a photo with your webcam'
                : 'Capture a photo with the front camera',
            icon: Icons.photo_camera_outlined,
            onTap: _loading ? null : _captureMoodPhotoFromCamera,
          ),
          const SizedBox(height: 10),
          _ScanOptionTile(
            title: 'Mood scan (video)',
            subtitle: kIsWeb
                ? 'Record a short clip with your webcam'
                : 'Record a short video with the front camera',
            icon: Icons.videocam_outlined,
            onTap: _loading ? null : _captureMoodVideoFromCamera,
          ),
          if (_imageMoodResult != null) ...[
            const SizedBox(height: 8),
            _SimpleMoodResultCard(
              title: 'Image Mood Result',
              payload: _imageMoodResult!,
            ),
          ],
          if (_videoMoodResult != null) ...[
            const SizedBox(height: 8),
            _SimpleMoodResultCard(
              title: 'Video Mood Result',
              payload: _videoMoodResult!,
            ),
          ],
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

enum AnalysisMode { fast, accurate }

class _AnalysisModeToggle extends StatelessWidget {
  const _AnalysisModeToggle({required this.mode, required this.onChanged});

  final AnalysisMode mode;
  final ValueChanged<AnalysisMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E6EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analysis Mode',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'Fast',
                  selected: mode == AnalysisMode.fast,
                  subtitle: 'Low response time',
                  onTap: onChanged == null ? null : () => onChanged!(AnalysisMode.fast),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeChip(
                  label: 'High Accuracy',
                  selected: mode == AnalysisMode.accurate,
                  subtitle: 'More detailed results',
                  onTap: onChanged == null ? null : () => onChanged!(AnalysisMode.accurate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6F39E8) : const Color(0xFFF6F4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF3A3B46),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: selected ? const Color(0xFFDACEFF) : const Color(0xFF7A7C8A),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisSessionCard extends StatelessWidget {
  const _AnalysisSessionCard({
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
    final topText = topStates.isEmpty ? 'N/A' : topStates.join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analysis Session Summary',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (analysisSource == 'emotion_model_fallback') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFB6D9F7)),
              ),
              child: Text(
                webStylePrediction.isNotEmpty
                    ? 'Web-style mood: $webStylePrediction '
                        '(${webStyleConfidence <= 1 ? (webStyleConfidence * 100).round() : webStyleConfidence.round()}% confidence)'
                    : 'Scores from the same emotion model as web (OpenFace had no face landmarks in this clip).',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A4A7A),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Dominant State: ${dominant.toUpperCase()}'),
          Row(
            children: [
              const Text('Overall Severity: '),
              MentalHealthScoreDisplay(
                percent: severity,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                labelFontWeight: FontWeight.w800,
              ),
            ],
          ),
          Text('Top Match States: $topText'),
          const SizedBox(height: 10),
          _ScoreCard(title: 'Stress', value: stress),
          const SizedBox(height: 8),
          _ScoreCard(title: 'Anxiety', value: anxiety),
          const SizedBox(height: 8),
          _ScoreCard(title: 'Depression', value: depression),
          const SizedBox(height: 10),
          _BulletCard(title: 'Facial Behavior Insights', items: behavioralInsights),
          const SizedBox(height: 10),
          _BulletCard(title: 'AI Recommendations', items: recommendations),
          const SizedBox(height: 10),
          _AusCard(aus: aus),
          const SizedBox(height: 10),
          _BulletCard(title: 'Active AUs (Actual OpenFace Detection)', items: activeAus),
          const SizedBox(height: 10),
          _AuDiseaseRelationCard(map: matchedAusByState),
          const SizedBox(height: 10),
          _StateProbabilityCard(probabilities: stateProbabilities),
          const SizedBox(height: 10),
          _DeepFaceSummaryCard(
            dominant: deepfaceDominant,
            framesAnalyzed: deepfaceFrames,
            summary: deepfaceSummary,
          ),
        ],
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

class _SimpleMoodResultCard extends StatelessWidget {
  const _SimpleMoodResultCard({required this.title, required this.payload});

  final String title;
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final prediction =
        (payload['prediction'] ?? payload['emotion'] ?? 'Unknown').toString();
    final confidence = (payload['confidence'] ?? '').toString();
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
          const SizedBox(height: 6),
          Text('Prediction: $prediction'),
          if (confidence.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Confidence: $confidence'),
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
