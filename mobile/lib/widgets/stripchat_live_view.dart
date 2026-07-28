import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-app WebView player (Stripchat rooms + generic site fallback).
/// Prefer real streams when GenericSiteApi can extract m3u8/mp4;
/// when parsing fails, the feed opens the detail page here instead of
/// jumping to system browser.
class StripchatLiveView extends StatelessWidget {
  const StripchatLiveView({
    super.key,
    required this.roomUrl,
    required this.muted,
    this.stripchatMode = true,
  });

  final String roomUrl;
  final bool muted;
  final bool stripchatMode;

  static const _control = MethodChannel('epickle/stripchat_live_control');

  static Future<void> setMuted(bool muted) async {
    try {
      await _control.invokeMethod<void>('setMuted', muted);
    } on PlatformException {
      // The platform view may be between rooms; the next view gets the value
      // from creationParams.
    } on MissingPluginException {
      // Tests / unsupported platforms do not register the native control channel.
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewType = 'epickle/stripchat_live';
    final params = <String, dynamic>{
      'url': roomUrl,
      'muted': muted,
      'stripchatMode': stripchatMode,
    };
    if (Platform.isIOS) {
      return UiKitView(
        key: ValueKey(roomUrl),
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return AndroidView(
      key: ValueKey(roomUrl),
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
