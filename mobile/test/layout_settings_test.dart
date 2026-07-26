import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/services/layout_settings.dart';
import 'package:phub_player/services/source_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('custom HTTPS URL keeps its explicit port and subpath', () async {
    final settings = LayoutSettings();

    await settings.addCustomUrl('https://fixture.test:8443/catalog/root/');

    expect(
      settings.customUrls,
      ['https://fixture.test:8443/catalog/root'],
    );
    final site = settings.enabledVideoSites.singleWhere((item) => item.custom);
    expect(site.primaryHost, 'https://fixture.test:8443/catalog/root');
    expect(site.id, contains(Uri.encodeComponent(site.primaryHost)));
  });

  test('custom URL rejects cleartext HTTP', () async {
    final settings = LayoutSettings();

    await settings.addCustomUrl('http://fixture.test/catalog');

    expect(settings.customUrls, isEmpty);
  });

  test('built-in duplicate detection compares host instead of substrings',
      () async {
    final settings = LayoutSettings();

    await settings.addCustomUrl('https://videos.com');

    expect(settings.customUrls, ['https://videos.com']);
    expect(SourceCatalog.all, isNotEmpty);
  });
}
