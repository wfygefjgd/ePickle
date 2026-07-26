import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/utils/http_headers.dart';
import 'package:phub_player/utils/playback_helpers.dart';

void main() {
  test('page headers look like iOS Safari navigation', () {
    final headers = AppHttpHeaders.forSite('https://fixture.test/watch/42');

    expect(AppHttpHeaders.userAgent, contains('iPhone'));
    expect(AppHttpHeaders.browser, isNot(contains('Origin')));
    expect(headers, isNot(contains('Origin')));
    expect(headers['Referer'], 'https://fixture.test/');
  });

  test('media headers retain the exact detail page as referer', () {
    final headers = AppHttpHeaders.forMediaUrl(
      'https://cdn.fixture.test/video/master.m3u8',
      pageUrl: 'https://fixture.test/watch/42?token=abc',
    );

    expect(headers['Referer'], 'https://fixture.test/watch/42?token=abc');
    expect(headers['Origin'], 'https://fixture.test');
  });

  test('iOS uses one preload decoder and Android uses at most two', () {
    expect(PlaybackHelpers.preloadSlotCount(TargetPlatform.iOS), 1);
    expect(PlaybackHelpers.preloadSlotCount(TargetPlatform.android), 2);
  });
}
