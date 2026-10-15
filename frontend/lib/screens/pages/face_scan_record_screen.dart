import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/behavior_analysis_warmup.dart';

/// Full-screen front-camera recorder for Deep Face Analysis (max 30s).
class FaceScanRecordScreen extends StatefulWidget {
  const FaceScanRecordScreen({super.key});

  @override
  State<FaceScanRecordScreen> createState() => _FaceScanRecordScreenState();
}

class _FaceScanRecordScreenState extends State<FaceScanRecordScreen> {
  static const int _maxDurationSeconds = 30;

  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  bool _stopInProgress = false;
  int _elapsed = 0;
  Timer? _timer;

  XFile? _recorded;
  VideoPlayerController? _playback;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(warmupBehaviorAnalysisModels());
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _disposePlayback() async {
    await _playback?.dispose();
    _playback = null;
    _recorded = null;
  }

  void _cancelRecordingTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _recording || _stopInProgress) {
      return;
    }
    try {
      await _disposePlayback();
      if (!mounted) return;
      setState(() {});

      await c.startVideoRecording();
      if (!mounted) return;

      _cancelRecordingTimer();
      setState(() {
        _recording = true;
        _elapsed = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_recording || _stopInProgress) {
          t.cancel();
          return;
        }
        setState(() => _elapsed += 1);
        if (_elapsed >= _maxDurationSeconds) {
          t.cancel();
          unawaited(_stopRecording(autoStop: true));
        }
      });
    } catch (e) {
      _cancelRecordingTimer();
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start recording: $e')),
      );
    }
  }

  Future<void> _initPlayback(XFile file) async {
    await _playback?.dispose();
    if (!mounted) return;
    VideoPlayerController ctrl;
    if (kIsWeb) {
      ctrl = VideoPlayerController.networkUrl(Uri.parse(file.path));
    } else {
      ctrl = VideoPlayerController.file(File(file.path));
    }
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 15));
    } catch (e) {
      await ctrl.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open preview: $e')),
      );
      return;
    }
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    await ctrl.setLooping(true);
    await ctrl.play();
    setState(() {
      _recorded = file;
      _playback = ctrl;
    });
  }

  /// User Stop always wins over the max-duration timer.
  Future<void> _stopRecording({bool autoStop = false}) async {
    if (_stopInProgress) return;
    if (!_recording) return;

    _stopInProgress = true;
    _cancelRecordingTimer();

    if (mounted) {
      setState(() => _recording = false);
    }

    final c = _controller;
    if (c == null) {
      _stopInProgress = false;
      return;
    }

    try {
      XFile? file;
      if (c.value.isRecordingVideo) {
        file = await c.stopVideoRecording();
      } else if (c.value.isRecordingPaused) {
        try {
          file = await c.stopVideoRecording();
        } catch (_) {
          // Already finalized on some devices.
        }
      }

      if (!mounted) return;
      if (file != null) {
        await _initPlayback(file);
      }
      if (autoStop && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-stopped at $_maxDurationSeconds seconds.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to stop recording: $e')),
        );
      }
    } finally {
      _stopInProgress = false;
    }
  }

  Future<void> _discardRecordingAndRetry() async {
    await _disposePlayback();
    if (!mounted) return;
    setState(() {
      _elapsed = 0;
    });
  }

  Future<void> _confirmRecording() async {
    final file = _recorded;
    if (file == null) return;
    if (!kIsWeb) {
      try {
        final f = File(file.path);
        for (var i = 0; i < 15; i++) {
          if (await f.length() >= 32_000) break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (await f.length() < 12_000) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Video is still saving. Wait for preview, then try again.',
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // Server validates if length check fails.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(file);
  }

  @override
  void dispose() {
    _cancelRecordingTimer();
    unawaited(_playback?.dispose());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final playback = _playback;
    final hasPlayback =
        playback != null && playback.value.isInitialized && _recorded != null;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Record face video'),
        centerTitle: true,
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : c == null
          ? const Center(
              child: Text(
                'Camera unavailable',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                if (hasPlayback)
                  Center(
                    child: AspectRatio(
                      aspectRatio: playback.value.aspectRatio,
                      child: VideoPlayer(playback),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final previewSize = c.value.previewSize;
                      if (previewSize == null) {
                        return Center(child: CameraPreview(c));
                      }
                      return ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: previewSize.height,
                            height: previewSize.width,
                            child: CameraPreview(c),
                          ),
                        ),
                      );
                    },
                  ),
                if (!hasPlayback)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 56),
                      if (_recording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB71C1C),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'REC  $_elapsed / $_maxDurationSeconds s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (!hasPlayback)
                        Text(
                          'Up to $_maxDurationSeconds seconds · front camera',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        child: hasPlayback
                            ? Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _discardRecordingAndRetry,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: Colors.white54,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      child: const Text('Record again'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () =>
                                          unawaited(_confirmRecording()),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF6F39E8),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      child: const Text('Use this video'),
                                    ),
                                  ),
                                ],
                              )
                            : _recording
                            ? SizedBox(
                                width: 88,
                                height: 88,
                                child: ElevatedButton(
                                  onPressed: _stopInProgress
                                      ? null
                                      : () => unawaited(
                                            _stopRecording(autoStop: false),
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    shape: const CircleBorder(),
                                    backgroundColor: const Color(0xFFB71C1C),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Icon(
                                    Icons.stop_rounded,
                                    size: 40,
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: 88,
                                height: 88,
                                child: ElevatedButton(
                                  onPressed: _startRecording,
                                  style: ElevatedButton.styleFrom(
                                    shape: const CircleBorder(),
                                    backgroundColor: const Color(0xFF6F39E8),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Icon(
                                    Icons.fiber_manual_record,
                                    size: 36,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
