import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages draggable button positions for video player controls.
class ButtonPositions extends ChangeNotifier {
  ButtonPositions() {
    _load();
  }

  // Default positions (right-aligned layout)
  Offset _fullscreenPos = const Offset(10, 120);
  Offset _settingsPos = const Offset(10, 180);
  Offset _volumePos = const Offset(10, 56);
  Offset _fastForwardPos = const Offset(10, 56); // left side

  Offset get fullscreenPos => _fullscreenPos;
  Offset get settingsPos => _settingsPos;
  Offset get volumePos => _volumePos;
  Offset get fastForwardPos => _fastForwardPos;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _fullscreenPos = Offset(
      prefs.getDouble('btn_fullscreen_x') ?? 10,
      prefs.getDouble('btn_fullscreen_y') ?? 120,
    );
    _settingsPos = Offset(
      prefs.getDouble('btn_settings_x') ?? 10,
      prefs.getDouble('btn_settings_y') ?? 180,
    );
    _volumePos = Offset(
      prefs.getDouble('btn_volume_x') ?? 10,
      prefs.getDouble('btn_volume_y') ?? 56,
    );
    _fastForwardPos = Offset(
      prefs.getDouble('btn_fastforward_x') ?? 10,
      prefs.getDouble('btn_fastforward_y') ?? 56,
    );
    notifyListeners();
  }

  Future<void> setFullscreenPos(Offset pos) async {
    _fullscreenPos = pos;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('btn_fullscreen_x', pos.dx);
    await prefs.setDouble('btn_fullscreen_y', pos.dy);
  }

  Future<void> setSettingsPos(Offset pos) async {
    _settingsPos = pos;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('btn_settings_x', pos.dx);
    await prefs.setDouble('btn_settings_y', pos.dy);
  }

  Future<void> setVolumePos(Offset pos) async {
    _volumePos = pos;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('btn_volume_x', pos.dx);
    await prefs.setDouble('btn_volume_y', pos.dy);
  }

  Future<void> setFastForwardPos(Offset pos) async {
    _fastForwardPos = pos;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('btn_fastforward_x', pos.dx);
    await prefs.setDouble('btn_fastforward_y', pos.dy);
  }
}
