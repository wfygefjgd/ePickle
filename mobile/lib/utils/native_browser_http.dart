import 'dart:io';

import 'package:flutter/services.dart';

class NativeBrowserHttpResponse {
  const NativeBrowserHttpResponse({
    required this.statusCode,
    required this.body,
    required this.finalUrl,
    required this.cookies,
  });

  final int statusCode;
  final String body;
  final String finalUrl;
  final Map<String, String> cookies;
}

/// iOS URLSession fallback for sites that reject Dart HttpClient's TLS stack.
/// This does not pretend a 403 means the site is down, and it keeps the native
/// redirect/cookie session used by subsequent fallback requests.
class NativeBrowserHttp {
  NativeBrowserHttp._();

  static const _channel = MethodChannel('epickle/browser_http');

  static Future<NativeBrowserHttpResponse?> get(
    String url, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('get', {
        'url': url,
        'headers': headers,
        'timeoutMs': timeout.inMilliseconds,
      });
      if (raw == null) return null;
      final cookieMap = <String, String>{};
      final cookies = raw['cookies'];
      if (cookies is Map) {
        for (final entry in cookies.entries) {
          cookieMap[entry.key.toString()] = entry.value.toString();
        }
      }
      return NativeBrowserHttpResponse(
        statusCode: (raw['statusCode'] as num?)?.toInt() ?? 0,
        body: raw['body']?.toString() ?? '',
        finalUrl: raw['finalUrl']?.toString() ?? url,
        cookies: cookieMap,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
