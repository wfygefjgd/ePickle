import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:epickle/services/generic_site_api.dart';
import 'package:epickle/services/mitao_api.dart';
import 'package:epickle/services/phub_api.dart';
import 'package:epickle/services/source_catalog.dart';
import 'package:epickle/services/xvideos_api.dart';

void main() {
  test('generic adapter propagates cancellation without trying more paths',
      () async {
    final adapter = _CancelAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    const site = SiteDef(
      id: 'cancel_fixture',
      name: 'Cancel fixture',
      kind: SiteKind.video,
      tags: [],
      color: 0,
      letter: 'C',
      mirrors: ['https://cancel.fixture.test'],
    );

    await expectLater(
      GenericSiteApi(dio: dio).fetchFeed(site, limit: 1),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, 1);
  });

  test('native fallback adapters do not retry after cancellation', () async {
    for (final api in <Future<List<Object>> Function()>[
      () => MitaoApi(dio: Dio()..httpClientAdapter = _CancelAdapter())
          .search('fixture'),
      () => XvideosApi(dio: Dio()..httpClientAdapter = _CancelAdapter())
          .search('fixture'),
    ]) {
      await expectLater(api(), throwsA(isA<DioException>()));
    }
  });

  test('native adapter reports HTTP 429 instead of parsing it as HTML',
      () async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _StatusAdapter(429, 'too many requests');

    await expectLater(
      PhubApi(dio: dio).search('fixture'),
      throwsA(
        isA<PhubException>().having(
          (error) => error.toString(),
          'message',
          contains('429'),
        ),
      ),
    );
  });
}

class _CancelAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
      error: 'test cancellation',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(body, statusCode);

  @override
  void close({bool force = false}) {}
}
