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
}

String _html(String body) => '<!doctype html><html><head>$body</head><body>'
    '${List.filled(400, 'fixture').join()}</body></html>';

class _FixtureResponse {
  const _FixtureResponse(
    this.body, {
    this.headers = const {},
  });

  final String body;
  final Map<String, List<String>> headers;
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
      200,
      headers: fixture.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
