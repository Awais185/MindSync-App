import 'package:flutter/material.dart';

import '../../widgets/mindsync_logo.dart';

/// Brief branded splash while session/bootstrap runs (first launch and cold start).
class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFEDE8FA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MindSyncLogo(height: 100, width: 160),
            SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF6F39E8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
