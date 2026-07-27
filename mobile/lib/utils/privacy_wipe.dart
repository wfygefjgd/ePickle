import 'package:flutter/services.dart';

/// Native privacy wipe: clears WebView data, cookies, cache, prefs, keychain.
class PrivacyWipe {
  static const _channel = MethodChannel('privacy_browser/engine');

  static Future<void> nuclearWipe() async {
    try {
      await _channel.invokeMethod<void>('nuclearWipe');
    } on PlatformException {
      // channel may be unavailable on some platforms; ignore
    } on MissingPluginException {
      // not registered; ignore
    }
  }

  static Future<void> exitApp() async {
    try {
      await _channel.invokeMethod<void>('exitApp');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}
