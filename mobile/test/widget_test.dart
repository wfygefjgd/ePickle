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

  testWidgets('Home search field stays above the iOS keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      PlayerApp(
        settings: AppSettings(),
        layout: LayoutSettings(),
        history: WatchHistory(),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField).first;
    final searchBar = find.byKey(const ValueKey('home_search_bar'));
    expect(tester.getBottomRight(searchField).dy, lessThan(220));
    expect(tester.getSize(searchBar).height, lessThan(70));
    expect(find.textContaining('ePickle'), findsOneWidget);
  });
}
