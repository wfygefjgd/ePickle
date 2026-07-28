import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_player.dart';
import 'services/app_settings.dart';
import 'services/cache_manager.dart';
import 'services/layout_settings.dart';
import 'services/watch_history.dart';
import 'utils/http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Smoother scrolling on high-refresh displays (paired with native mode pick).
  if (Platform.isAndroid) {
    // ignore: unawaited_futures
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Android: Dio must learn system HTTP proxy before first feed request.
  // WebView already follows system proxy; Dart HttpClient does not.
  await AppHttpClient.refreshSystemProxy();

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
