import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosKeyboardInsets extends ChangeNotifier {
  IosKeyboardInsets._() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  static final IosKeyboardInsets instance = IosKeyboardInsets._();
  static const _channel = MethodChannel('epickle/keyboard_insets');

  double _bottom = 0;
  Duration _animationDuration = const Duration(milliseconds: 180);

  double get bottom => _bottom;
  Duration get animationDuration => _animationDuration;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'keyboardFrameChanged') return;
    final values = Map<Object?, Object?>.from(call.arguments as Map);
    final bottom = (values['bottom'] as num?)?.toDouble() ?? 0;
    final durationMs = (values['durationMs'] as num?)?.round() ?? 180;
    _update(bottom, Duration(milliseconds: durationMs));
  }

  void _update(double bottom, Duration duration) {
    final nextBottom = math.max(0.0, bottom);
    if (_bottom == nextBottom && _animationDuration == duration) return;
    _bottom = nextBottom;
    _animationDuration = duration;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetBottom(double bottom) {
    _update(bottom, Duration.zero);
  }
}

class KeyboardAvoidingBottomBar extends StatelessWidget {
  const KeyboardAvoidingBottomBar({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardInsets = IosKeyboardInsets.instance;
    return AnimatedBuilder(
      animation: keyboardInsets,
      child: child,
      builder: (context, child) {
        final mediaBottom = MediaQuery.viewInsetsOf(context).bottom;
        final bottom = math.max(mediaBottom, keyboardInsets.bottom);
        return AnimatedPadding(
          duration: keyboardInsets.animationDuration,
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottom),
          child: child,
        );
      },
    );
  }
}
