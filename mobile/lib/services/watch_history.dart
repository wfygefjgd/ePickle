import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';

/// Local watch history (newest first). Survives app restarts.
class WatchHistory extends ChangeNotifier {
  static const _kKey = 'watch_history_v1';
  static const maxItems = 100;

  final List<VideoItem> _items = [];
  bool _ready = false;

  bool get ready => _ready;
  List<VideoItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    _items.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final url = (m['url'] as String?)?.trim() ?? '';
          if (url.isEmpty) continue;
          _items.add(VideoItem(
            url: url,
            title: (m['title'] as String?)?.trim() ?? '',
            duration: (m['duration'] as String?)?.trim() ?? '-',
            thumb: (m['thumb'] as String?)?.trim(),
          ));
        }
      } catch (_) {}
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> record(VideoItem item) async {
    final url = item.url.trim();
    if (url.isEmpty) return;
    _items.removeWhere((e) => e.viewkey == item.viewkey || e.url == url);
    _items.insert(
      0,
      VideoItem(
        url: url,
        title: item.title,
        duration: item.duration,
        thumb: item.thumb,
      ),
    );
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(VideoItem item) async {
    final before = _items.length;
    _items.removeWhere(
      (e) => e.viewkey == item.viewkey || e.url == item.url,
    );
    if (_items.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    final data = _items
        .map((e) => {
              'url': e.url,
              'title': e.title,
              'duration': e.duration,
              'thumb': e.thumb,
            })
        .toList();
    await p.setString(_kKey, jsonEncode(data));
  }
}
