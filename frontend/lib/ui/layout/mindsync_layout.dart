import 'package:flutter/material.dart';

class MindSyncSpacing {
  const MindSyncSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

class MindSyncLayout {
  const MindSyncLayout._();

  static const double maxContentWidth = 520;

  static double horizontalPaddingForWidth(double width) {
    if (width < 360) return 16;
    if (width < 420) return 18;
    return 20;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return horizontalPaddingForWidth(width);
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 16,
    double bottom = 100,
  }) {
    final hp = horizontalPadding(context);
    return EdgeInsets.fromLTRB(hp, top, hp, bottom);
  }

  static Widget constrainContent(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}
