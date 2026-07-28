import 'package:flutter_test/flutter_test.dart';
import 'package:epickle/services/layout_settings.dart';
import 'package:epickle/services/source_catalog.dart';
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

  test('hidden sites are removed from home/search sources and persist',
      () async {
    final settings = LayoutSettings();

    await settings.setSiteHidden(SourceCatalog.pornhub, true);

    expect(settings.isSiteHidden(SourceCatalog.pornhub), isTrue);
    expect(
      settings.enabledVideoSites.map((site) => site.id),
      isNot(contains('pornhub')),
    );

    final restored = LayoutSettings();
    await restored.load();
    expect(restored.isSiteHidden(SourceCatalog.pornhub), isTrue);
    expect(
      restored.enabledVideoSites.map((site) => site.id),
      isNot(contains('pornhub')),
    );
  });

  test('hidden live site cannot remain the default live entry', () async {
    final settings = LayoutSettings();

    await settings.setSiteHidden(SourceCatalog.chaturbate, true);

    expect(settings.liveSite?.id, isNot('chaturbate'));
  });
}
