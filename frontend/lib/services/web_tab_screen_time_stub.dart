/// Non-web platforms: no tab visibility tracking.
class WebTabScreenTime {
  static void start(void Function(int seconds) onTick) {}

  static void stop() {}

  static int get seconds => 0;
}
