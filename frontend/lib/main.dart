import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config/api_config.dart';
import 'utils/stripe_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await initializeStripePublishableKey();
  }
  await ApiConfig.initialize();
  runApp(const MindSyncApp());
}
