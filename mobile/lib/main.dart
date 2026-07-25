import 'package:flutter/material.dart';

import 'app_player.dart';
import 'services/app_settings.dart';
import 'services/cache_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings();
  await settings.load();

  // Auto-check and clean cache on app launch
  CacheManager.checkAndCleanIfNeeded();

  runApp(PlayerApp(settings: settings));
}
