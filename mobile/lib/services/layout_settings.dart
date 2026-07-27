import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'source_catalog.dart';

/// Home site list + search/live prefs (not playback/proxy).
class LayoutSettings extends ChangeNotifier {
  static const _kEnabled = 'layout_enabled_video_ids_v1';
  static const _kLiveId = 'layout_live_id_v1';
  static const _kGlobalSearch = 'layout_global_search_v1';
  static const _kCatalogVer = 'layout_catalog_ver_v1';
  static const _kCustomUrls = 'layout_custom_urls_v1';
  static const _catalogVer = 9;

  List<String> _enabledVideoIds =
      List<String>.from(SourceCatalog.defaultEnabledVideoIds);
  List<String> _customUrls = [];
  String _liveId = SourceCatalog.defaultLiveId;
  bool _globalSearch = false;
  bool _ready = false;

  bool get ready => _ready;
  List<String> get enabledVideoIds => List.unmodifiable(_enabledVideoIds);
  List<String> get customUrls => List.unmodifiable(_customUrls);
  String get liveId => _liveId;
  bool get globalSearch => _globalSearch;

  List<SiteDef> get enabledVideoSites {
    final out = <SiteDef>[];
    for (final id in _enabledVideoIds) {
      final s = SourceCatalog.byId(id);
      if (s != null && s.kind == SiteKind.video && s.ready) out.add(s);
    }
    for (final u in _customUrls) {
      out.add(SiteDef.customFromUrl(u));
    }
    return out;
  }

  SiteDef? get liveSite {
    final site = SourceCatalog.byId(_liveId);
    return site?.ready == true ? site : SourceCatalog.chaturbate;
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final catVer = p.getInt(_kCatalogVer) ?? 0;
      if (catVer < _catalogVer) {
        _enabledVideoIds =
            List<String>.from(SourceCatalog.defaultEnabledVideoIds);
        await p.setStringList(_kEnabled, _enabledVideoIds);
        await p.setInt(_kCatalogVer, _catalogVer);
      } else {
        final raw = p.getStringList(_kEnabled);
        if (raw != null && raw.isNotEmpty) {
          _enabledVideoIds = raw
              .where((id) => SourceCatalog.byId(id)?.kind == SiteKind.video)
              .toList();
        }
        if (_enabledVideoIds.isEmpty) {
          _enabledVideoIds =
              List<String>.from(SourceCatalog.defaultEnabledVideoIds);
        }
      }
      final live = p.getString(_kLiveId);
      if (live != null &&
          SourceCatalog.byId(live)?.kind == SiteKind.live &&
          SourceCatalog.byId(live)?.ready == true) {
        _liveId = live;
      }
      _globalSearch = p.getBool(_kGlobalSearch) ?? false;
      _customUrls = p.getStringList(_kCustomUrls) ?? [];
    } catch (_) {
      _enabledVideoIds =
          List<String>.from(SourceCatalog.defaultEnabledVideoIds);
      _liveId = SourceCatalog.defaultLiveId;
      _globalSearch = false;
      _customUrls = [];
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> addCustomUrl(String raw) async {
    var u = raw.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    // Custom adapters carry cookies and media referrers, so only accept TLS.
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final path =
        uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/+$'), '');
    final normalized = Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
    if (_customUrls.contains(normalized)) return;
    // Also skip if already a built-in mirror
    for (final s in SourceCatalog.all) {
      for (final m in s.mirrors) {
        final builtIn = Uri.tryParse(m);
        if (builtIn != null &&
            builtIn.host == uri.host &&
            builtIn.port == uri.port) {
          return;
        }
      }
    }
    _customUrls = [..._customUrls, normalized];
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kCustomUrls, _customUrls);
    } catch (_) {}
  }

  Future<void> removeCustomUrl(String url) async {
    _customUrls = _customUrls.where((e) => e != url).toList();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kCustomUrls, _customUrls);
    } catch (_) {}
  }

  Future<void> setEnabledVideoIds(List<String> ids) async {
    final clean = ids
        .where((id) => SourceCatalog.byId(id)?.kind == SiteKind.video)
        .toList();
    if (clean.isEmpty) {
      clean.addAll(List<String>.from(SourceCatalog.defaultEnabledVideoIds));
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
    final site = SourceCatalog.byId(id);
    if (site?.kind != SiteKind.live || site?.ready != true) return;
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
    _enabledVideoIds = List<String>.from(SourceCatalog.defaultEnabledVideoIds);
    _liveId = SourceCatalog.defaultLiveId;
    _globalSearch = false;
    _customUrls = [];
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kEnabled, _enabledVideoIds);
      await p.setString(_kLiveId, _liveId);
      await p.setBool(_kGlobalSearch, false);
      await p.setStringList(_kCustomUrls, _customUrls);
      await p.setInt(_kCatalogVer, _catalogVer);
    } catch (_) {}
  }
}
