import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-app WebView player (Stripchat rooms + generic site fallback).
/// Prefer real streams when GenericSiteApi can extract m3u8/mp4;
/// when parsing fails, the feed opens the detail page here instead of
/// jumping to system browser.
class StripchatLiveView extends StatefulWidget {
  const StripchatLiveView({
    super.key,
    required this.roomUrl,
    required this.muted,
    this.stripchatMode = true,
    this.onSkip,
  });

  final String roomUrl;
  final bool muted;
  final bool stripchatMode;
  final VoidCallback? onSkip;

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
  State<StripchatLiveView> createState() => _StripchatLiveViewState();
}

class _StripchatLiveViewState extends State<StripchatLiveView> {
  @override
  void initState() {
    super.initState();
    StripchatLiveView._control.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    StripchatLiveView._control.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'skip') {
      widget.onSkip?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewType = 'epickle/stripchat_live';
    final params = <String, dynamic>{
      'url': widget.roomUrl,
      'muted': widget.muted,
      'stripchatMode': widget.stripchatMode,
    };
    if (Platform.isIOS) {
      return UiKitView(
        key: ValueKey(widget.roomUrl),
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return AndroidView(
      key: ValueKey(widget.roomUrl),
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
