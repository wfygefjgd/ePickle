import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Automatic cache cleanup with throttling (avoid scanning temp every video).
class CacheManager {
  static const _maxCacheSizeMB = 500;
  static const _targetCacheSizeMB = 300;
  static const _minInterval = Duration(minutes: 30);
  static const _minVideosBetween = 40;

  static DateTime? _lastCheck;
  static int _videosSinceCheck = 0;
  static bool _running = false;

  /// On launch: force one check (still throttled against concurrent runs).
  static Future<void> checkAndCleanIfNeeded({bool force = false}) async {
    if (_running) return;
    final now = DateTime.now();
    if (!force) {
      _videosSinceCheck++;
      if (_lastCheck != null &&
          now.difference(_lastCheck!) < _minInterval &&
          _videosSinceCheck < _minVideosBetween) {
        return;
      }
    }
    _running = true;
    _lastCheck = now;
    _videosSinceCheck = 0;
    try {
      final cacheSize = await _getCacheSizeInMB();
      if (cacheSize > _maxCacheSizeMB) {
        debugPrint('Cache size ${cacheSize.toStringAsFixed(0)}MB exceeds limit, cleaning...');
        await _cleanCache();
        final newSize = await _getCacheSizeInMB();
        debugPrint(
          'Cache cleaned: ${cacheSize.toStringAsFixed(0)}MB → ${newSize.toStringAsFixed(0)}MB',
        );
      }
    } catch (e) {
      debugPrint('Cache check failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Call after a successful play (throttled).
  static void onVideoPlayed() {
    // ignore: discarded_futures
    checkAndCleanIfNeeded();
  }

  static Future<double> _getCacheSizeInMB() async {
    try {
      final tempDir = await getTemporaryDirectory();
      // Prefer flutter_cache_manager / libCachedImageData dirs if present.
      final candidates = <Directory>[
        Directory('${tempDir.path}/libCachedImageData'),
        Directory('${tempDir.path}/flutter_cache_manager'),
        tempDir,
      ];
      Directory? root;
      for (final d in candidates) {
        if (await d.exists()) {
          root = d;
          // Prefer specific cache dirs over whole temp.
          if (d.path != tempDir.path) break;
        }
      }
      if (root == null) return 0;

      int totalSize = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }
      return totalSize / (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _cleanCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();

      Future<void> deleteOlderThan(int days) async {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final stat = await entity.stat();
              if (now.difference(stat.modified).inDays > days) {
                await entity.delete();
              }
            } catch (_) {}
          }
        }
      }

      await deleteOlderThan(7);
      final currentSize = await _getCacheSizeInMB();
      if (currentSize > _targetCacheSizeMB) {
        await deleteOlderThan(3);
      }
    } catch (e) {
      debugPrint('Cache cleanup failed: $e');
    }
  }

  static Future<void> clearAllCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      final tempDir = await getTemporaryDirectory();
      await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
