import 'dart:async';
import 'dart:html' as html;

/// Counts seconds while the browser tab is visible (Flutter web).
class WebTabScreenTime {
  WebTabScreenTime._();

  static Timer? _timer;
  static int _seconds = 0;
  static void Function(int seconds)? _onTick;

  static int get seconds => _seconds;

  static void start(void Function(int seconds) onTick) {
    stop();
    _onTick = onTick;
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (html.document.visibilityState == 'visible') {
        _seconds++;
        _onTick?.call(_seconds);
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _onTick = null;
  }
}
