import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'http_headers.dart';
import 'system_proxy.dart';

/// Shared Dio factory.
///
/// Android note: Dart HttpClient does NOT follow system proxy/VPN UI the way
/// WebView does. We therefore:
/// 1) use user manual proxy if set
/// 2) else use Android system proxy (Clash/V2Ray 系统代理)
/// 3) else DIRECT (TUN mode / no proxy)
class AppHttpClient {
  AppHttpClient._();

  static bool proxyEnabled = false;
  static String proxyHost = '';
  static int proxyPort = 0;
  static String proxyType = 'http';

  /// Auto-detected system proxy (Android). Used when no manual proxy.
  static String? _systemHost;
  static int _systemPort = 0;
  static String _systemType = 'http';
  static bool _systemReady = false;

  static void applyProxyConfig({
    required bool enabled,
    required String host,
    required int port,
    required String type,
  }) {
    proxyHost = host.trim();
    proxyPort = (port > 0 && port < 65536) ? port : 0;
    proxyType = type == 'socks5' ? 'socks5' : 'http';
    proxyEnabled = enabled && proxyHost.isNotEmpty && proxyPort > 0;
  }

  /// Refresh Android system proxy for Dio. Safe to call often.
  static Future<void> refreshSystemProxy() async {
    try {
      final info = await SystemProxy.detect();
      if (info != null) {
        _systemHost = info.host;
        _systemPort = info.port;
        _systemType = info.type;
      } else {
        _systemHost = null;
        _systemPort = 0;
        _systemType = 'http';
      }
    } catch (_) {
      _systemHost = null;
      _systemPort = 0;
    }
    _systemReady = true;
  }

  static String _findProxy(Uri uri) {
    // 1) Manual proxy wins.
    if (proxyEnabled && proxyHost.isNotEmpty && proxyPort > 0) {
      final h = proxyHost;
      final p = proxyPort;
      if (proxyType == 'socks5') {
        return 'SOCKS5 $h:$p; SOCKS $h:$p; DIRECT';
      }
      return 'PROXY $h:$p; DIRECT';
    }
    // 2) Android system proxy (browser works; Dio must be told explicitly).
    final sh = _systemHost;
    if (sh != null && sh.isNotEmpty && _systemPort > 0) {
      if (_systemType == 'socks5') {
        return 'SOCKS5 $sh:$_systemPort; SOCKS $sh:$_systemPort; DIRECT';
      }
      return 'PROXY $sh:$_systemPort; DIRECT';
    }
    // 3) TUN / clean device.
    return 'DIRECT';
  }

  static Dio create({
    Map<String, dynamic>? headers,
    Duration connectTimeout = const Duration(seconds: 18),
    Duration receiveTimeout = const Duration(seconds: 28),
    CancelToken? cancelToken,
  }) {
    // Kick off system proxy detect once if not ready (non-blocking).
    if (!_systemReady) {
      // ignore: discarded_futures
      refreshSystemProxy();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          ...AppHttpHeaders.browser,
          if (headers != null) ...headers,
        },
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (s) => s != null && s < 500,
        responseType: ResponseType.plain,
      ),
    );

    if (cancelToken != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.cancelToken = cancelToken;
            handler.next(options);
          },
        ),
      );
    }

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = connectTimeout;
        client.idleTimeout = const Duration(seconds: 30);
        client.autoUncompress = true;
        client.userAgent = AppHttpHeaders.userAgent;
        // Critical on Android: without this, Dio ignores system HTTP proxy
        // while WebView still works → "browser OK, app lists fail".
        client.findProxy = _findProxy;
        return client;
      },
    );

    return dio;
  }
}
