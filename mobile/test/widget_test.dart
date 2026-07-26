import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/app_player.dart';
import 'package:phub_player/services/app_settings.dart';
import 'package:phub_player/services/layout_settings.dart';
import 'package:phub_player/services/watch_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Player app builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    final layout = LayoutSettings();
    final history = WatchHistory();
    await tester.pumpWidget(
      PlayerApp(settings: settings, layout: layout, history: history),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
