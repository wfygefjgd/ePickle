import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Immersive UI chrome. Avoids aggressive orientation APIs on Android
/// (can hard-crash Android 15 emulators / GPU host).
class PlayerChrome extends ChangeNotifier {
  bool _immersive = false;

  bool get immersive => _immersive;

  bool get _isAndroid {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<void> enterFullscreen({DeviceOrientation? preferredOrientation}) async {
    if (_immersive) return;
    _immersive = true;
    notifyListeners();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    // Only rotate on iOS — Android uses current device orientation to avoid
    // emulator GPU deaths when forcing landscape from app code.
    if (!_isAndroid) {
      try {
        // 如果指定了方向，强制使用该方向；否则允许两个横屏方向
        if (preferredOrientation != null) {
          await SystemChrome.setPreferredOrientations([preferredOrientation]);
        } else {
          await SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } catch (_) {}
    }
  }

  Future<void> exitFullscreen() async {
    if (!_immersive) return;
    _immersive = false;
    notifyListeners();
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}
    if (!_isAndroid) {
      try {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } catch (_) {}
    }
  }

  Future<void> toggleFullscreen({DeviceOrientation? preferredOrientation}) async {
    if (_immersive) {
      await exitFullscreen();
    } else {
      await enterFullscreen(preferredOrientation: preferredOrientation);
    }
  }

  Future<void> ensurePortraitChrome() async {
    if (_immersive) {
      await exitFullscreen();
    }
  }
}
