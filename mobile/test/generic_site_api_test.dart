import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/services/generic_site_api.dart';
import 'package:phub_player/services/source_catalog.dart';

void main() {
  const site = SiteDef(
    id: 'fixture',
    name: 'Fixture',
    kind: SiteKind.video,
    tags: [],
    color: 0,
    letter: 'F',
    mirrors: ['https://fixture.test'],
  );

  test('resolves relative streams and reversed meta attributes', () async {
    const pageUrl = 'https://fixture.test/videos/42/index.html';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <meta content="Fixture &amp; title" property="og:title">
          <meta content="../../images/cover.jpg" property="og:image">
          <script>window.player = {"file":"../../media/master.m3u8?token=1"};</script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(detail.title, 'Fixture & title');
    expect(detail.thumb, 'https://fixture.test/images/cover.jpg');
    expect(
      detail.streams.map((stream) => stream.url),
      contains('https://fixture.test/media/master.m3u8?token=1'),
    );
  });

  test('follows iframe paths relative to each document and carries cookies',
      () async {
    const pageUrl = 'https://fixture.test/watch/42/index.html';
    const embedUrl = 'https://fixture.test/players/42/index.html';
    final adapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('<iframe src="../../../players/42/index.html"></iframe>'),
        headers: const {
          'set-cookie': ['session=abc123; Path=/; HttpOnly'],
        },
      ),
      embedUrl: _FixtureResponse(
        _html('<video><source src="../media/full.mp4"></video>'),
      ),
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(
      detail.streams.map((stream) => stream.url),
      contains('https://fixture.test/players/media/full.mp4'),
    );
    final embedRequest = adapter.requests.singleWhere(
      (request) => request.uri.toString() == embedUrl,
    );
    expect(embedRequest.headers['Cookie'], contains('session=abc123'));
    expect(embedRequest.headers['Referer'], pageUrl);
  });

  test('decodes MacCMS base64 player URLs', () async {
    const pageUrl = 'https://fixture.test/vod/play/99/index.html';
    const mediaUrl = 'https://cdn.fixture.test/full/master.m3u8';
    final encoded = base64Encode(utf8.encode(mediaUrl));
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>
            var player_aaaa = {"url":"$encoded","encrypt":2};
          </script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(detail.streams.map((stream) => stream.url), contains(mediaUrl));
  });

  test('decodes escaped HLS URLs and ignores image src fields', () async {
    const pageUrl = 'https://fixture.test/watch/escaped';
    const mediaUrl =
        'https://cdn.fixture.test/live/master.m3u8?token=a&expires=2';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html(r'''
          <script>
            window.config = {
              "src":"https://fixture.test/poster.jpg?cache=1",
              "hlsUrl":"https:\/\/cdn.fixture.test\/live\/master.m3u8?token=a\u0026expires=2"
            };
          </script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(detail.streams.map((stream) => stream.url), contains(mediaUrl));
    expect(
      detail.streams.map((stream) => stream.url),
      everyElement(isNot(contains('poster.jpg'))),
    );
  });

  test('reads reversed og:video attributes and lazy source attributes',
      () async {
    const pageUrl = 'https://fixture.test/watch/meta/index.html';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <meta content="../../media/master.m3u8?x=1&amp;y=2"
                property="og:video">
          <video><source data-src="../../media/fallback.mp4"></video>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(
      detail.streams.map((stream) => stream.url),
      contains('https://fixture.test/media/master.m3u8?x=1&y=2'),
    );
    expect(
      detail.streams.map((stream) => stream.url),
      contains('https://fixture.test/media/fallback.mp4'),
    );
  });

  test('normalizes KVS function URLs and rejects MP4 thumbnail URLs', () async {
    const pageUrl = 'https://fixture.test/embed/32176';
    const mediaUrl =
        'https://fixture.test/get_file/7/abc/32176.mp4/?embed=true';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>
            video_alt_url1: 'function/0/https://img.test/32176.mp4.jpg',
            video_url: 'function/0/$mediaUrl'
          </script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);
    final urls = detail.streams.map((stream) => stream.url);

    expect(urls, contains(mediaUrl));
    expect(urls, everyElement(isNot(endsWith('.mp4.jpg'))));
  });

  test('prefers KVS embed media and carries its referrer and session cookie',
      () async {
    const pageUrl = 'https://fixture.test/video/32176/example/';
    const embedUrl = 'https://fixture.test/embed/32176';
    const mediaUrl =
        'https://fixture.test/get_file/3/hash/32176.mp4/?embed=true';
    const javSite = SiteDef(
      id: 'javmix',
      name: 'JAVMix fixture',
      kind: SiteKind.video,
      tags: [],
      color: 0,
      letter: 'J',
      mirrors: ['https://fixture.test'],
    );
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>video_url: "https://fixture.test/get_file/3/hash/32176.mp4/"</script>
          <iframe src="$embedUrl"></iframe>
        '''),
        headers: const {
          'set-cookie': ['PHPSESSID=session123; Path=/'],
        },
      ),
      embedUrl: _FixtureResponse(
        _html('''
          <script>video_url: "function/0/$mediaUrl"</script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(
      javSite,
      pageUrl,
    );
    final stream = detail.streams.first;

    expect(stream.url, mediaUrl);
    expect(stream.referer, embedUrl);
    expect(stream.headers['Cookie'], contains('PHPSESSID=session123'));
  });

  test('decrypts Our55 DES player data into the full HLS URL', () async {
    const pageUrl = 'https://fixture.test/vod/play/42.html';
    const mediaUrl = 'https://cdn2.shayubf.com/20200222/Tlr76hci/index.m3u8';
    const encrypted =
        'xkoiCz64PL0ivzt27wOsj5aJ5r8Xvt9P5cmuIFXPJizNxnJ2pA3oiyZrIiY2yTE5gtx7f539bcJrKNJfiHy2hslOy1hD2E+k';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>
            window.config = {
              video: {
                id: '56b0f1d57700712f2e77ea43f4624ad6',
                data: ['$encrypted']
              }
            };
          </script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(detail.streams.map((stream) => stream.url), contains(mediaUrl));
  });

  test('decrypts Our55 payloads containing JSON-escaped base64 slashes',
      () async {
    const pageUrl = 'https://fixture.test/video/current.html';
    const encrypted =
        r'2JRsK7P1DMg82YkW7R2L3VoMnVluQ\/MlmuoQ9vWrAqaR6WPNHxIA5de9GRjKvoERxZMhZ9hXSW8VOqWtUV\/55qkagjY8Klnt';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>
            const config = {
              video: {
                id: '0dc2f831bc834dd6a67240a64cffbf6c',
                data: ["$encrypted"]
              }
            };
          </script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(
      SourceCatalog.our55,
      pageUrl,
    );

    expect(detail.streams, isNotEmpty);
    expect(detail.streams.first.url, contains('.m3u8'));
  });

  test('filters Eporner unavailable clip and parses minute duration', () async {
    const pageUrl = 'https://fixture.test/watch/eporner';
    const mediaUrl = 'https://cdn.fixture.test/full.mp4';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <span class="vid-length">17min</span>
          <video>
            <source src="https://static.eporner.com/na.mp4">
            <source src="$mediaUrl">
          </video>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);
    final urls = detail.streams.map((stream) => stream.url);

    expect(detail.durationSec, 1020);
    expect(urls, contains(mediaUrl));
    expect(urls, everyElement(isNot(contains('static.eporner.com/na.mp4'))));
  });

  test('parses ISO 8601 video duration metadata', () async {
    const pageUrl = 'https://fixture.test/watch/long';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <meta itemprop="duration" content="P0DT2H15M0S">
          <video src="https://cdn.fixture.test/full.mp4"></video>
        '''),
      ),
    });

    final detail = await GenericSiteApi(dio: dio).getVideoDetail(site, pageUrl);

    expect(detail.durationSec, 8100);
  });

  test('prefers Stripchat auto HLS playlist for a stream name', () async {
    const pageUrl = 'https://fixture.test/model_name';
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      pageUrl: _FixtureResponse(
        _html('''
          <script>window.initialState = {"streamName":"live_model_42"};</script>
        '''),
      ),
    });

    final detail = await GenericSiteApi(
      dio: dio,
    ).getVideoDetail(SourceCatalog.stripchat, pageUrl);

    expect(detail.streams.first.url, contains('live_model_42_auto.m3u8'));
  });

  test('races mirrors and records distinct mirror health', () async {
    const failedBase = 'https://failed.fixture.test';
    const workingBase = 'https://working.fixture.test';
    const mirrorSite = SiteDef(
      id: 'mirror_fixture',
      name: 'Mirror Fixture',
      kind: SiteKind.video,
      tags: [],
      color: 0,
      letter: 'M',
      mirrors: [failedBase, workingBase],
    );
    final dio = Dio();
    dio.httpClientAdapter = _FixtureAdapter({
      '$failedBase/videos?page=1&sort=hot':
          const _FixtureResponse('forbidden', statusCode: 403),
      '$workingBase/videos?page=1&sort=hot': _FixtureResponse(
        _html('''
          <a href="/video/fixture-42" title="Working mirror video">
            <img src="/cover.jpg">
          </a>
        '''),
      ),
    });
    final api = GenericSiteApi(dio: dio);

    final feed = await api.fetchFeed(mirrorSite, limit: 1);
    final health = api.mirrorHealthFor(mirrorSite.id);

    expect(feed, hasLength(1));
    expect(feed.single.url, '$workingBase/video/fixture-42');
    expect(
      health.singleWhere((entry) => entry.url == failedBase).failure,
      MirrorFailureKind.forbidden,
    );
    expect(
      health.singleWhere((entry) => entry.url == workingBase).isAvailable,
      isTrue,
    );
  });

  test('directory-only FreePorn is not enabled as a playable source', () {
    expect(SourceCatalog.freeporn.ready, isFalse);
    expect(SourceCatalog.defaultEnabledVideoIds, isNot(contains('freeporn')));
  });

  test('catalog exposes the seven verified playable channels', () {
    expect(
      SourceCatalog.defaultEnabledVideoIds,
      unorderedEquals([
        'pornhub',
        'xvideos',
        'mitao',
        'xnxx',
        'our55',
        'xqq88',
      ]),
    );
    expect(SourceCatalog.defaultLiveId, 'chaturbate');
    expect(SourceCatalog.chaturbate.ready, isTrue);
    expect(SourceCatalog.stripchat.ready, isFalse);
  });
}

String _html(String body) => '<!doctype html><html><head>$body</head><body>'
    '${List.filled(400, 'fixture').join()}</body></html>';

class _FixtureResponse {
  const _FixtureResponse(
    this.body, {
    this.headers = const {},
    this.statusCode = 200,
  });

  final String body;
  final Map<String, List<String>> headers;
  final int statusCode;
}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.fixtures);

  final Map<String, _FixtureResponse> fixtures;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final fixture = fixtures[options.uri.toString()];
    if (fixture == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      fixture.body,
      fixture.statusCode,
      headers: fixture.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
