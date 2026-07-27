import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-app WKWebView player (Stripchat rooms + generic site fallback).
/// Prefer real AVPlayer streams when GenericSiteApi can extract m3u8/mp4;
/// when parsing fails, the feed opens the detail page here instead of
/// jumping to system Safari.
class StripchatLiveView extends StatelessWidget {
  const StripchatLiveView({
    super.key,
    required this.roomUrl,
    required this.muted,
  });

  final String roomUrl;
  final bool muted;

  static const _control = MethodChannel('epickle/stripchat_live_control');

  static Future<void> setMuted(bool muted) async {
    if (!Platform.isIOS) return;
    try {
      await _control.invokeMethod<void>('setMuted', muted);
    } on PlatformException {
      // The platform view may be between rooms; the next view gets the value
      // from creationParams.
    } on MissingPluginException {
      // Non-iOS tests do not register the native control channel.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Stripchat live playback is currently available on iOS only',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return UiKitView(
      key: ValueKey(roomUrl),
      viewType: 'epickle/stripchat_live',
      layoutDirection: TextDirection.ltr,
      creationParams: <String, dynamic>{
        'url': roomUrl,
        'muted': muted,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
