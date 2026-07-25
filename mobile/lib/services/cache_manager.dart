import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Automatic cache cleanup manager.
/// Monitors cache size and auto-cleans when threshold is reached.
class CacheManager {
  static const _maxCacheSizeMB = 500; // 500MB threshold
  static const _targetCacheSizeMB = 300; // Clean down to 300MB

  /// Check cache size and clean if needed.
  /// Call this periodically (e.g., on app launch, after video loads).
  static Future<void> checkAndCleanIfNeeded() async {
    try {
      final cacheSize = await _getCacheSizeInMB();
      if (cacheSize > _maxCacheSizeMB) {
        debugPrint('Cache size ${cacheSize}MB exceeds limit, cleaning...');
        await _cleanCache();
        final newSize = await _getCacheSizeInMB();
        debugPrint('Cache cleaned: ${cacheSize}MB → ${newSize}MB');
      }
    } catch (e) {
      debugPrint('Cache check failed: $e');
    }
  }

  /// Get total cache size in MB.
  static Future<double> _getCacheSizeInMB() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(tempDir.path);

      if (!await cacheDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }

      return totalSize / (1024 * 1024); // Convert to MB
    } catch (_) {
      return 0;
    }
  }

  /// Clean cache down to target size.
  static Future<void> _cleanCache() async {
    try {
      // Clean cached_network_image cache
      await DefaultCacheManager().emptyCache();

      // Also clean old files from temp directory
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();

      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);

            // Delete files older than 7 days
            if (age.inDays > 7) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }

      // Check if we need more aggressive cleaning
      final currentSize = await _getCacheSizeInMB();
      if (currentSize > _targetCacheSizeMB) {
        // Delete files older than 3 days
        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is File) {
            try {
              final stat = await entity.stat();
              final age = now.difference(stat.modified);

              if (age.inDays > 3) {
                await entity.delete();
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Cache cleanup failed: $e');
    }
  }

  /// Manual cache clear (for settings page if needed).
  static Future<void> clearAllCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      final tempDir = await getTemporaryDirectory();

      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
