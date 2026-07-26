import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'source_catalog.dart';

/// Home site list + search/live prefs (not playback/proxy).
class LayoutSettings extends ChangeNotifier {
  static const _kEnabled = 'layout_enabled_video_ids_v1';
  static const _kLiveId = 'layout_live_id_v1';
  static const _kGlobalSearch = 'layout_global_search_v1';

  List<String> _enabledVideoIds = List.from(SourceCatalog.defaultEnabledVideoIds);
  String _liveId = SourceCatalog.defaultLiveId;
  bool _globalSearch = false;
  bool _ready = false;

  bool get ready => _ready;
  List<String> get enabledVideoIds => List.unmodifiable(_enabledVideoIds);
  String get liveId => _liveId;
  bool get globalSearch => _globalSearch;

  List<SiteDef> get enabledVideoSites {
    final out = <SiteDef>[];
    for (final id in _enabledVideoIds) {
      final s = SourceCatalog.byId(id);
      if (s != null && s.kind == SiteKind.video) out.add(s);
    }
    return out;
  }

  SiteDef? get liveSite => SourceCatalog.byId(_liveId);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_kEnabled);
      if (raw != null && raw.isNotEmpty) {
        _enabledVideoIds = raw
            .where((id) => SourceCatalog.byId(id)?.kind == SiteKind.video)
            .toList();
      }
      if (_enabledVideoIds.isEmpty) {
        _enabledVideoIds = List.from(SourceCatalog.defaultEnabledVideoIds);
      }
      final live = p.getString(_kLiveId);
      if (live != null && SourceCatalog.byId(live)?.kind == SiteKind.live) {
        _liveId = live;
      }
      _globalSearch = p.getBool(_kGlobalSearch) ?? false;
    } catch (_) {
      _enabledVideoIds = List.from(SourceCatalog.defaultEnabledVideoIds);
      _liveId = SourceCatalog.defaultLiveId;
      _globalSearch = false;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> setEnabledVideoIds(List<String> ids) async {
    final clean = ids
        .where((id) => SourceCatalog.byId(id)?.kind == SiteKind.video)
        .toList();
    if (clean.isEmpty) {
      clean.addAll(SourceCatalog.defaultEnabledVideoIds);
    }
    _enabledVideoIds = clean;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kEnabled, _enabledVideoIds);
    } catch (_) {}
  }

  Future<void> toggleVideoSite(String id, bool enabled) async {
    final next = List<String>.from(_enabledVideoIds);
    if (enabled) {
      if (!next.contains(id)) next.add(id);
    } else {
      next.remove(id);
      if (next.isEmpty) return; // keep at least one
    }
    await setEnabledVideoIds(next);
  }

  Future<void> reorderVideo(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _enabledVideoIds.length) return;
    var ni = newIndex;
    if (ni > oldIndex) ni -= 1;
    final id = _enabledVideoIds.removeAt(oldIndex);
    _enabledVideoIds.insert(ni.clamp(0, _enabledVideoIds.length), id);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kEnabled, _enabledVideoIds);
    } catch (_) {}
  }

  Future<void> setLiveId(String id) async {
    if (SourceCatalog.byId(id)?.kind != SiteKind.live) return;
    _liveId = id;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLiveId, id);
    } catch (_) {}
  }

  Future<void> setGlobalSearch(bool v) async {
    if (_globalSearch == v) return;
    _globalSearch = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kGlobalSearch, v);
    } catch (_) {}
  }

  /// Restore source + home layout only (not proxy / quality).
  Future<void> restoreDefaultLayout() async {
    _enabledVideoIds = List.from(SourceCatalog.defaultEnabledVideoIds);
    _liveId = SourceCatalog.defaultLiveId;
    _globalSearch = false;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kEnabled, _enabledVideoIds);
      await p.setString(_kLiveId, _liveId);
      await p.setBool(_kGlobalSearch, false);
    } catch (_) {}
  }
}
