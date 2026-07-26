import 'package:flutter/material.dart';

import 'app_player.dart';
import 'services/app_settings.dart';
import 'services/cache_manager.dart';
import 'services/layout_settings.dart';
import 'services/watch_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings();
  await settings.load();

  final layout = LayoutSettings();
  await layout.load();

  final history = WatchHistory();
  await history.load();

  // Throttled; force once on cold start.
  // ignore: unawaited_futures
  CacheManager.checkAndCleanIfNeeded(force: true);

  runApp(PlayerApp(
    settings: settings,
    layout: layout,
    history: history,
  ));
}
