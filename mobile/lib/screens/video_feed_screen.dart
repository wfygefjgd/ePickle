import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../services/xvideos_api.dart';
import '../services/app_settings.dart';
import '../services/cache_manager.dart';
import '../services/feed_list_cache.dart';
import '../services/player_chrome.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/video_player_page.dart';

enum VideoFeedKind {
  hot,
  asian,
  x,
  zhong,
}

/// Vertical feed with one active VideoPlayerController plus one silent
/// pre-buffered next-video controller for instant swipe (TikTok-style).
/// Designed for Android stability (ExoPlayer + multi-instance freezes).
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({
    super.key,
    this.kind = VideoFeedKind.hot,
    this.autoStart = false,
  });

  final VideoFeedKind kind;
  final bool autoStart;

  @override
  State<VideoFeedScreen> createState() => VideoFeedScreenState();
}

class VideoFeedScreenState extends State<VideoFeedScreen>
    with WidgetsBindingObserver {
  final List<VideoItem> _items = [];
  final Set<String> _seen = {};
  late final PageController _pageCtrl;

  /// Only the currently playing controller (never multiple).
  VideoPlayerController? _controller;
  int _currentIndex = 0;
  int _loadSeq = 0;

  /// Pre-buffered next video controller (paused, muted) for instant swipe.
  VideoPlayerController? _preloadController;
  int? _preloadIndex;
  StreamQuality? _preloadStream;
  int _preloadRetries = 0;

  VideoPlayerController? _preloadController2;
  int? _preloadIndex2;
  StreamQuality? _preloadStream2;
  int _preloadRetries2 = 0;

  VideoPlayerController? _preloadController3;
  int? _preloadIndex3;
  StreamQuality? _preloadStream3;
  int _preloadRetries3 = 0;

  bool _loading = false;
  bool _loadingMore = false;
  bool _pageLoading = false;
  bool _muted = false;
  bool _active = false;
  String? _error;
  String _titleText = '';
  String _speedLabel = '';

  Timer? _progressTimer;
  Timer? _retryTimer;
  Timer? _skipTimer;
  Timer? _loadMoreTimer;
  final ValueNotifier<double> _sliderValue = ValueNotifier(0);
  final ValueNotifier<String> _currentTime = ValueNotifier('0:00');
  String _totalTime = '0:00';
  int _baseSpeed = 1500;
  double _lastBufferedMs = 0;
  int _lastTickMs = 0;
  double _lastPosMs = 0;
  String _lastSpeedLabel = '';
  int _failStreak = 0;
  final Map<int, VideoDetail> _detailCache = {};
  int? _prefetchingIndex;
  bool _seeking = false;
  VideoDetail? _currentDetail;
  PlayerChrome? _chrome;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  bool _wasLandscape = false;
  DateTime? _lastOrientationChange;
  String get _cacheKey => widget.kind.name;
  late final Map<String, String> _httpHeaders = _buildHeaders();

  /// Get current video URL for sharing
  String? getCurrentVideoUrl() {
    if (_currentIndex < 0 || _currentIndex >= _items.length) return null;
    return _items[_currentIndex].url;
  }

  Map<String, String> _buildHeaders() {
    switch (widget.kind) {
      case VideoFeedKind.x:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://www.xvideos.com/',
          'Origin': 'https://www.xvideos.com',
        };
      case VideoFeedKind.zhong:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://mitaohk.com/',
          'Origin': 'https://mitaohk.com',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      case VideoFeedKind.hot:
      case VideoFeedKind.asian:
        return AppHttpHeaders.browser;
    }
  }

  String get _feedLabel {
    switch (widget.kind) {
      case VideoFeedKind.asian:
        return '亚';
      case VideoFeedKind.x:
        return 'X';
      case VideoFeedKind.zhong:
        return '中';
      case VideoFeedKind.hot:
        return '热';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome ??= context.read<PlayerChrome>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = context.read<AppSettings>().muted;
    final snap = FeedListCache.take(_cacheKey);
    if (snap != null && snap.items.isNotEmpty) {
      _items.addAll(snap.items);
      _seen.addAll(snap.seen);
      _currentIndex = snap.index.clamp(0, _items.length - 1);
      _loading = false;
    }
    _pageCtrl = PageController(initialPage: _currentIndex);
    _startAccelerometerListener();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startPlaying();
      });
    }
  }

  @override
  void dispose() {
    if (_items.isNotEmpty) {
      FeedListCache.put(
        _cacheKey,
        FeedListSnapshot(
          items: List<VideoItem>.from(_items),
          seen: Set<String>.from(_seen),
          index: _currentIndex,
        ),
      );
    }
    // Do not use context after dispose; cached chrome only
    try {
      _chrome?.ensurePortraitChrome();
    } catch (_) {}
    _accelSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _retryTimer?.cancel();
    _skipTimer?.cancel();
    _loadMoreTimer?.cancel();
    _sliderValue.dispose();
    _currentTime.dispose();
    _pageCtrl.dispose();
    final c = _controller;
    _controller = null;
    try {
      c?.dispose();
    } catch (_) {}
    _disposePreloadSync();
    WakelockPlus.disable();
    super.dispose();
  }

  void _disposePreloadSync() {
    final p = _preloadController;
    _preloadController = null;
    _preloadIndex = null;
    _preloadStream = null;
    _preloadRetries = 0;
    if (p != null) {
      // ignore: unawaited_futures
      p.pause().catchError((_) {}).whenComplete(() {
        try {
          p.dispose();
        } catch (_) {}
      });
    }

    final p2 = _preloadController2;
    _preloadController2 = null;
    _preloadIndex2 = null;
    _preloadStream2 = null;
    _preloadRetries2 = 0;
    if (p2 != null) {
      // ignore: unawaited_futures
      p2.pause().catchError((_) {}).whenComplete(() {
        try {
          p2.dispose();
        } catch (_) {}
      });
    }

    final p3 = _preloadController3;
    _preloadController3 = null;
    _preloadIndex3 = null;
    _preloadStream3 = null;
    _preloadRetries3 = 0;
    if (p3 != null) {
      // ignore: unawaited_futures
      p3.pause().catchError((_) {}).whenComplete(() {
        try {
          p3.dispose();
        } catch (_) {}
      });
    }
  }

  Future<void> _toggleFullscreen() async {
    await context.read<PlayerChrome>().toggleFullscreen();
    if (mounted) setState(() {});
  }

  void _startAccelerometerListener() {
    final settings = context.read<AppSettings>();
    _accelSubscription = accelerometerEventStream().listen((event) {
      if (!settings.autoRotate || !mounted) return;

      final chrome = _chrome;
      if (chrome == null) return;

      // 防抖：距离上次方向改变至少 1200ms
      final now = DateTime.now();
      if (_lastOrientationChange != null &&
          now.difference(_lastOrientationChange!) < const Duration(milliseconds: 1200)) {
        return;
      }

      // 检测横屏：x 轴绝对值明显大于 y 轴，且 x 足够大
      // 阈值提高到 8.5，y 轴必须小于 4.0
      final xAbs = event.x.abs();
      final yAbs = event.y.abs();
      final isLandscape = xAbs > yAbs && xAbs > 8.5 && yAbs < 4.0;

      if (isLandscape && !_wasLandscape && !chrome.immersive) {
        // 手机刚横置且当前是竖屏 → 自动进入横屏
        // 根据 x 的正负判断方向：x > 0 是 landscapeRight，x < 0 是 landscapeLeft
        _wasLandscape = true;
        _lastOrientationChange = now;
        final orientation = event.x > 0
            ? DeviceOrientation.landscapeRight
            : DeviceOrientation.landscapeLeft;
        chrome.enterFullscreen(preferredOrientation: orientation);
        if (mounted) setState(() {});
      } else if (!isLandscape && _wasLandscape && chrome.immersive) {
        // 手机刚竖置且当前是横屏 → 自动退出横屏
        _wasLandscape = false;
        _lastOrientationChange = now;
        chrome.exitFullscreen();
        if (mounted) setState(() {});
      } else if (!isLandscape) {
        _wasLandscape = false;
      } else if (isLandscape) {
        _wasLandscape = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
      _preloadController?.pause();
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed && _active) {
      _controller?.play();
      WakelockPlus.enable();
    }
  }

  void startPlaying() {
    _active = true;
    if (_items.isEmpty) {
      if (!_loadingMore) {
        setState(() => _loading = true);
        _loadMore();
      }
      return;
    }
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.play();
      _startProgressTimer();
      WakelockPlus.enable();
      return;
    }
    _playIndex(_currentIndex);
  }

  void pausePlayback({bool releasePlayers = true}) {
    _active = false;
    _loadSeq++;
    _progressTimer?.cancel();
    _progressTimer = null;
    final c = _controller;
    _controller = null;
    try {
      c?.pause();
    } catch (_) {}
    _disposePreloadSync();
    WakelockPlus.disable();
    if (releasePlayers && c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          c.dispose();
        } catch (_) {}
      });
    }
  }

  Future<List<VideoItem>> _fetchBatch({required bool isCold}) {
    // Cold: few URLs, fail fast (less spinner). Warm: more variety.
    final limit = isCold ? 10 : 30;
    final maxUrls = isCold ? 2 : 5;
    switch (widget.kind) {
      case VideoFeedKind.asian:
        return context.read<PhubApi>().fetchAsian(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.hot:
        return context.read<PhubApi>().fetchRecommend(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.x:
        return context.read<XvideosApi>().fetchFeed(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.zhong:
        return context.read<MitaoApi>().fetchZhong(
              exclude: _seen,
              limit: limit,
              maxPages: maxUrls,
            );
    }
  }

  Future<VideoDetail> _fetchDetail(String url) {
    if (url.contains('xvideos.com') || widget.kind == VideoFeedKind.x) {
      return context.read<XvideosApi>().getVideoDetail(url);
    }
    if (url.contains('mitaohk.com') || widget.kind == VideoFeedKind.zhong) {
      return context.read<MitaoApi>().getVideoDetail(url);
    }
    return context.read<PhubApi>().getVideoDetail(url);
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    final isCold = _items.isEmpty;
    try {
      var list = await _fetchBatch(isCold: isCold);
      if (list.isEmpty && isCold) {
        list = await _fetchBatch(isCold: false);
      }
      final addedStart = _items.length;
      for (final item in list) {
        if (_seen.add(item.viewkey)) _items.add(item);
      }
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loading = false;
        if (_items.isEmpty) {
          _error = '$_feedLabel暂无内容。\n'
              '若需代理才能访问：设置→网络代理→重新检测，或开 TUN。';
        }
      });
      // PH / X titles are English — batch translate after list load.
      if (widget.kind != VideoFeedKind.zhong && _items.length > addedStart) {
        // ignore: unawaited_futures
        _translateItemsRange(addedStart);
      }
      if (_active && _items.isNotEmpty && _controller == null) {
        _playIndex(_currentIndex.clamp(0, _items.length - 1));
      }
      if (isCold && _items.length < 20 && _active) {
        _loadMoreTimer?.cancel();
        _loadMoreTimer = Timer(const Duration(seconds: 1), () {
          if (mounted && _active) _loadMore();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) {
          _error = PlaybackHelpers.friendlyError(e);
        } else if (mounted) {
          PlaybackHelpers.toast(
            context,
            '加载更多失败：${PlaybackHelpers.friendlyError(e)}',
          );
        }
      });
    }
  }

  final Set<int> _retried = {};

  void _scheduleSkipToNext(int fromIndex) {
    if (!_active) return;
    if (!_retried.contains(fromIndex)) {
      _retried.add(fromIndex);
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted || !_active) return;
        _playIndex(fromIndex);
      });
      return;
    }
    _failStreak++;
    if (_failStreak >= 3) {
      // Pause auto-play after 3 consecutive failures
      _failStreak = 0;
      _active = false;
      if (mounted) {
        PlaybackHelpers.toast(
          context,
          '连续多个视频无法播放。已暂停自动播放，请检查网络或代理设置',
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }
    if (mounted) PlaybackHelpers.toast(context, '已跳过无法播放的视频');
    final next = fromIndex + 1;
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !_active) return;
      if (next < _items.length) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(next);
        } else {
          _playIndex(next);
        }
      } else {
        _loadMore();
      }
    });
  }

  Future<void> _prefetchDetail(int index) async {
    if (!_active || index < 0 || index >= _items.length) return;
    if (_detailCache.containsKey(index)) return;
    if (_prefetchingIndex == index) return;
    _prefetchingIndex = index;
    final url = _items[index].url;
    try {
      final d = await _fetchDetail(url);
      if (!mounted || !_active) return;
      _detailCache[index] = d;
      _detailCache.removeWhere((k, _) => (k - _currentIndex).abs() > 3);
    } catch (_) {
      // Ignore errors in prefetch
    } finally {
      if (_prefetchingIndex == index) _prefetchingIndex = null;
    }
  }

  void _disposePreload() {
    final p = _preloadController;
    _preloadController = null;
    _preloadIndex = null;
    _preloadStream = null;
    _preloadRetries = 0;
    if (p != null) {
      // ignore: unawaited_futures
      p.pause().catchError((_) {}).whenComplete(() {
        try {
          p.dispose();
        } catch (_) {}
      });
    }

    final p2 = _preloadController2;
    _preloadController2 = null;
    _preloadIndex2 = null;
    _preloadStream2 = null;
    _preloadRetries2 = 0;
    if (p2 != null) {
      // ignore: unawaited_futures
      p2.pause().catchError((_) {}).whenComplete(() {
        try {
          p2.dispose();
        } catch (_) {}
      });
    }

    final p3 = _preloadController3;
    _preloadController3 = null;
    _preloadIndex3 = null;
    _preloadStream3 = null;
    _preloadRetries3 = 0;
    if (p3 != null) {
      // ignore: unawaited_futures
      p3.pause().catchError((_) {}).whenComplete(() {
        try {
          p3.dispose();
        } catch (_) {}
      });
    }
  }

  Future<void> _preloadNext(int index) async {
    if (!_active ||
        index < 0 ||
        index >= _items.length ||
        index == _currentIndex) {
      return;
    }
    if (_preloadIndex == index && _preloadController != null) return;
    final seq = _loadSeq;
    final detail = _detailCache[index];
    if (detail == null) return;
    if (detail.countryBlocked || detail.unavailable) return;
    final cap = context.read<AppSettings>().qualityCap;
    final stream =
        PlaybackHelpers.pickStream(detail, cap) ?? detail.bestStream;
    if (stream == null) return;
    if (_preloadIndex == index &&
        _preloadController != null &&
        _preloadStream?.url == stream.url) {
      return;
    }
    final existing = _preloadController;
    final existingIndex = _preloadIndex;
    _preloadController = null;
    _preloadIndex = null;
    _preloadStream = null;
    _preloadRetries = 0;
    if (existing != null && existingIndex != index) {
      // ignore: unawaited_futures
      existing.pause().catchError((_) {}).whenComplete(() {
        try {
          existing.dispose();
        } catch (_) {}
      });
    }
    if (seq != _loadSeq || !_active) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries < 2 && seq == _loadSeq && _active) {
        _preloadRetries++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries));
        if (seq == _loadSeq && _active && mounted) {
          return _preloadNext(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _loadSeq || !_active || mounted == false) {
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    _preloadController = player;
    _preloadIndex = index;
    _preloadStream = stream;
    _preloadRetries = 0;
    try {
      await player.pause();
      player.setVolume(0);
    } catch (_) {}
  }

  Future<void> _preloadNext2(int index) async {
    if (!_active ||
        index < 0 ||
        index >= _items.length ||
        index == _currentIndex) {
      return;
    }
    if (_preloadIndex2 == index && _preloadController2 != null) return;
    final seq = _loadSeq;
    final detail = _detailCache[index];
    if (detail == null) return;
    if (detail.countryBlocked || detail.unavailable) return;
    final cap = context.read<AppSettings>().qualityCap;
    final stream =
        PlaybackHelpers.pickStream(detail, cap) ?? detail.bestStream;
    if (stream == null) return;
    if (_preloadIndex2 == index &&
        _preloadController2 != null &&
        _preloadStream2?.url == stream.url) {
      return;
    }
    final existing = _preloadController2;
    final existingIndex = _preloadIndex2;
    _preloadController2 = null;
    _preloadIndex2 = null;
    _preloadStream2 = null;
    _preloadRetries2 = 0;
    if (existing != null && existingIndex != index) {
      // ignore: unawaited_futures
      existing.pause().catchError((_) {}).whenComplete(() {
        try {
          existing.dispose();
        } catch (_) {}
      });
    }
    if (seq != _loadSeq || !_active) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries2 = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries2 < 2 && seq == _loadSeq && _active) {
        _preloadRetries2++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries2));
        if (seq == _loadSeq && _active && mounted) {
          return _preloadNext2(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _loadSeq || !_active || mounted == false) {
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    _preloadController2 = player;
    _preloadIndex2 = index;
    _preloadStream2 = stream;
    _preloadRetries2 = 0;
    try {
      await player.pause();
      player.setVolume(0);
    } catch (_) {}
  }

  Future<void> _preloadNext3(int index) async {
    if (!_active ||
        index < 0 ||
        index >= _items.length ||
        index == _currentIndex) {
      return;
    }
    if (_preloadIndex3 == index && _preloadController3 != null) return;
    final seq = _loadSeq;
    final detail = _detailCache[index];
    if (detail == null) return;
    if (detail.countryBlocked || detail.unavailable) return;
    final cap = context.read<AppSettings>().qualityCap;
    final stream =
        PlaybackHelpers.pickStream(detail, cap) ?? detail.bestStream;
    if (stream == null) return;
    if (_preloadIndex3 == index &&
        _preloadController3 != null &&
        _preloadStream3?.url == stream.url) {
      return;
    }
    final existing = _preloadController3;
    final existingIndex = _preloadIndex3;
    _preloadController3 = null;
    _preloadIndex3 = null;
    _preloadStream3 = null;
    _preloadRetries3 = 0;
    if (existing != null && existingIndex != index) {
      // ignore: unawaited_futures
      existing.pause().catchError((_) {}).whenComplete(() {
        try {
          existing.dispose();
        } catch (_) {}
      });
    }
    if (seq != _loadSeq || !_active) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries3 = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries3 < 2 && seq == _loadSeq && _active) {
        _preloadRetries3++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries3));
        if (seq == _loadSeq && _active && mounted) {
          return _preloadNext3(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _loadSeq || !_active || mounted == false) {
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    _preloadController3 = player;
    _preloadIndex3 = index;
    _preloadStream3 = stream;
    _preloadRetries3 = 0;
    try {
      await player.pause();
      player.setVolume(0);
    } catch (_) {}
  }

  Future<void> _playIndex(int index) async {
    if (!_active || index < 0 || index >= _items.length) return;
    final seq = ++_loadSeq;
    final item = _items[index];

    // Check if we have this index preloaded in any slot
    VideoPlayerController? preloaded;
    VideoDetail? preloadDetail;
    StreamQuality? preloadStream;
    int preloadSlot = 0; // 1, 2, or 3

    if (_preloadIndex == index &&
        _preloadController != null &&
        _preloadController!.value.isInitialized) {
      preloaded = _preloadController!;
      preloadDetail = _detailCache[index];
      preloadStream = _preloadStream;
      preloadSlot = 1;
    } else if (_preloadIndex2 == index &&
        _preloadController2 != null &&
        _preloadController2!.value.isInitialized) {
      preloaded = _preloadController2!;
      preloadDetail = _detailCache[index];
      preloadStream = _preloadStream2;
      preloadSlot = 2;
    } else if (_preloadIndex3 == index &&
        _preloadController3 != null &&
        _preloadController3!.value.isInitialized) {
      preloaded = _preloadController3!;
      preloadDetail = _detailCache[index];
      preloadStream = _preloadStream3;
      preloadSlot = 3;
    }

    if (preloaded != null) {
      final previous = _controller;
      _controller = null;

      // Clear the slot that was used
      if (preloadSlot == 1) {
        _preloadController = null;
        _preloadIndex = null;
        _preloadStream = null;
      } else if (preloadSlot == 2) {
        _preloadController2 = null;
        _preloadIndex2 = null;
        _preloadStream2 = null;
      } else if (preloadSlot == 3) {
        _preloadController3 = null;
        _preloadIndex3 = null;
        _preloadStream3 = null;
      }

      await _disposeController(seqGuard: seq, exclude: preloaded);
      if (previous != null && !identical(previous, preloaded)) {
        try {
          await previous.pause();
        } catch (_) {}
        // ignore: unawaited_futures
        previous.dispose().catchError((_) {});
      }
      if (!mounted || seq != _loadSeq || !_active) {
        try {
          await preloaded.dispose();
        } catch (_) {}
        return;
      }
      _failStreak = 0;
      _currentDetail = preloadDetail;
      _currentIndex = index;
      final settings = context.read<AppSettings>();
      _muted = settings.muted;
      preloaded.setVolume(_muted ? 0 : 1);
      if (preloadDetail != null) {
        await PlaybackHelpers.skipIntro(preloaded, enabled: settings.skipIntro);
      }
      if (!mounted || seq != _loadSeq || !_active) {
        try {
          await preloaded.dispose();
        } catch (_) {}
        return;
      }
      _controller = preloaded;
      final dur = preloaded.value.duration;
      setState(() {
        _pageLoading = false;
        _titleText = preloadDetail?.title ?? item.title;
        _totalTime = PlaybackHelpers.fmtDuration(dur);
        _baseSpeed = preloadStream != null
            ? _estimateBaseSpeed(preloadStream.height)
            : 1500;
      });
      _sliderValue.value = 0;
      _currentTime.value = '0:00';
      if (preloadDetail != null) {
        _translateTitleOnly(preloadDetail.title);
      }
      await preloaded.play();
      _startProgressTimer();
      WakelockPlus.enable();
      if (mounted) setState(() {});

      // Promote preload2 to preload1, preload3 to preload2
      if (_preloadController2 != null && _preloadIndex2 == index + 1) {
        _preloadController = _preloadController2;
        _preloadIndex = _preloadIndex2;
        _preloadStream = _preloadStream2;
        _preloadRetries = _preloadRetries2;
        _preloadController2 = _preloadController3;
        _preloadIndex2 = _preloadIndex3;
        _preloadStream2 = _preloadStream3;
        _preloadRetries2 = _preloadRetries3;
        _preloadController3 = null;
        _preloadIndex3 = null;
        _preloadStream3 = null;
        _preloadRetries3 = 0;
      } else {
        // Preload next if not already preloaded
        await _prefetchDetail(index + 1);
        // ignore: unawaited_futures
        _preloadNext(index + 1);
      }
      // Always preload index+2 and index+3
      await _prefetchDetail(index + 2);
      await _prefetchDetail(index + 3);
      // ignore: unawaited_futures
      _preloadNext2(index + 2);
      // ignore: unawaited_futures
      _preloadNext3(index + 3);

      // Clean up old detail cache to prevent memory growth
      _cleanupDetailCache(index);
      return;
    }

    _disposePreload();

    // Tear down previous player completely before creating a new one
    await _disposeController();

    if (!mounted || seq != _loadSeq || !_active) return;
    setState(() {
      _pageLoading = true;
      _currentIndex = index;
      _titleText = item.title;
      _totalTime = '0:00';
      _speedLabel = '';
    });
    _sliderValue.value = 0;
    _currentTime.value = '0:00';

    VideoDetail detail;
    try {
      if (_detailCache.containsKey(index)) {
        detail = _detailCache[index]!;
      } else {
        detail = await _fetchDetail(item.url);
        _detailCache[index] = detail;
      }
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(
        context,
        '详情加载失败：${PlaybackHelpers.friendlyError(e)}',
      );
      _scheduleSkipToNext(index);
      return;
    }
    if (!mounted || seq != _loadSeq || !_active) return;

    if (detail.countryBlocked) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '该视频在当前地区不可用，已跳过');
      _scheduleSkipToNext(index);
      return;
    }
    if (detail.unavailable) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '视频不可用，已跳过');
      _scheduleSkipToNext(index);
      return;
    }

    final settings = context.read<AppSettings>();

    // Start preloading next three videos immediately after detail is loaded
    // Wait for detail to be fetched before preloading
    await _prefetchDetail(index + 1);
    await _prefetchDetail(index + 2);
    await _prefetchDetail(index + 3);
    // ignore: unawaited_futures
    _preloadNext(index + 1);
    // ignore: unawaited_futures
    _preloadNext2(index + 2);
    // ignore: unawaited_futures
    _preloadNext3(index + 3);

    // Quality: only what user set in settings. No auto fallback / stall switch.
    final stream =
        PlaybackHelpers.pickStream(detail, settings.qualityCap) ?? detail.bestStream;
    if (stream == null) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '无可用播放地址，已跳过');
      _scheduleSkipToNext(index);
      return;
    }

    _currentDetail = detail;
    _baseSpeed = _estimateBaseSpeed(stream.height);

    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
    } catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      if (mounted && seq == _loadSeq) {
        setState(() => _pageLoading = false);
        final tip = settings.proxyEnabled && settings.hasProxyEndpoint
            ? (settings.proxyType == 'socks5'
                ? '列表可能已通，但播放器常不跟 SOCKS。可开 TUN，或改用 HTTP 代理后重试'
                : '列表可能已通，播放仍失败。可开 TUN，或检查代理是否支持视频流')
            : '播放失败。若列表能出、播不动：开 TUN，或设置里配置 HTTP 代理';
        PlaybackHelpers.toast(context, tip, duration: const Duration(seconds: 3));
        _scheduleSkipToNext(index);
      }
      return;
    }
    if (!mounted || seq != _loadSeq || !_active) {
      await player.dispose();
      return;
    }

    _failStreak = 0;
    _muted = settings.muted;
    player.setVolume(_muted ? 0 : 1);

    // For videos >50min, skip to 1min mark instead of just the intro
    final totalSec = player.value.duration.inSeconds;
    if (totalSec >= 3000) {
      // >50min: jump to 1min (60s)
      try {
        await player.seekTo(const Duration(seconds: 60));
      } catch (_) {}
    } else {
      // Normal intro skip
      await PlaybackHelpers.skipIntro(player, enabled: settings.skipIntro);
    }

    if (!mounted || seq != _loadSeq || !_active) {
      await player.dispose();
      return;
    }
    _controller = player;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = PlaybackHelpers.fmtDuration(player.value.duration);
    });
    _translateTitleOnly(detail.title);
    await player.play();
    _startProgressTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});

    // Auto-check cache after video load
    CacheManager.checkAndCleanIfNeeded();

    // Clean up old detail cache to prevent memory growth
    _cleanupDetailCache(index);
  }

  Future<void> _disposeController({int? seqGuard, VideoPlayerController? exclude}) async {
    _progressTimer?.cancel();
    _progressTimer = null;
    final c = _controller;
    _controller = null;
    if (c == null || identical(c, exclude)) return;
    if (seqGuard != null && seqGuard != _loadSeq) return;
    try {
      await c.pause();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  void _startProgressTimer() {
    final ctrl = _controller;
    if (ctrl == null) return;
    _progressTimer?.cancel();
    _lastBufferedMs = 0;
    _lastTickMs = 0;
    _lastPosMs = 0;
    // 200ms feels smoother than 400ms; skip UI while user is dragging.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!identical(ctrl, _controller) || !ctrl.value.isInitialized) {
        _progressTimer?.cancel();
        _progressTimer = null;
        return;
      }
      // Skip update while seeking, but keep timer alive
      if (_seeking) return;

      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      if (dur.inMilliseconds <= 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ranges = ctrl.value.buffered;
      final bufMs = ranges.isEmpty
          ? 0.0
          : ranges.last.end.inMilliseconds.toDouble();
      final posMs = pos.inMilliseconds.toDouble();
      if (_lastTickMs > 0) {
        final dMs = now - _lastTickMs;
        final dBuf = bufMs - _lastBufferedMs;
        final dPlayed = posMs - _lastPosMs;
        final downloaded = (dBuf + dPlayed).clamp(0.0, double.infinity);
        if (dMs > 0 && downloaded > 0) {
          final ratio = (downloaded / dMs).clamp(0.0, 3.0);
          final speed = (_baseSpeed * ratio).round().clamp(0, 20000);
          final label = '$speed Kbps';
          if (label != _lastSpeedLabel) {
            _lastSpeedLabel = label;
            if (mounted) setState(() => _speedLabel = label);
          }
        }
      }
      _lastBufferedMs = bufMs;
      _lastTickMs = now;
      _lastPosMs = posMs;
      _sliderValue.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _currentTime.value = PlaybackHelpers.fmtDuration(pos);
      if (dur.inMilliseconds > 0) {
        final t = PlaybackHelpers.fmtDuration(dur);
        if (t != _totalTime && mounted) {
          setState(() => _totalTime = t);
        }
      }
    });
  }

  void _onPageChanged(int page) {
    if (page == _currentIndex) return;
    _retried.removeWhere((i) => (i - page).abs() > 3);
    // Hard switch: dispose old, play new only
    _playIndex(page);
    if (page >= _items.length - 3) {
      _loadMore();
    }
  }

  Future<void> _translateTitleOnly(String title) async {
    if (title.isEmpty) return;
    // Already Chinese (e.g. 中 tab) — keep as-is.
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) {
      if (mounted) setState(() => _titleText = title);
      return;
    }
    try {
      final zh = await context.read<Translator>().enToZh(title);
      if (!mounted || zh.isEmpty) return;
      setState(() => _titleText = zh);
      // Also update list item so next swipe shows Chinese immediately.
      final i = _currentIndex;
      if (i >= 0 && i < _items.length && _items[i].title == title) {
        _items[i] = _items[i].copyWith(title: zh);
      }
    } catch (_) {}
  }

  /// Batch-translate newly loaded English titles; prioritize near current index.
  Future<void> _translateItemsRange(int start) async {
    if (start < 0 || start >= _items.length) return;
    if (widget.kind == VideoFeedKind.zhong) return;
    try {
      final slice = _items.sublist(start);
      final urls = slice.map((e) => e.url).toList();
      final titles = slice.map((e) => e.title).toList();
      // Translate current neighborhood first (snappier UI), then the rest.
      final order = List<int>.generate(titles.length, (i) => i);
      order.sort((a, b) {
        final da = ((start + a) - _currentIndex).abs();
        final db = ((start + b) - _currentIndex).abs();
        return da.compareTo(db);
      });
      final orderedTitles = [for (final i in order) titles[i]];
      final zhOrdered =
          await context.read<Translator>().batchEnToZh(orderedTitles);
      if (!mounted) return;
      final zh = List<String>.filled(titles.length, '');
      for (var k = 0; k < order.length; k++) {
        zh[order[k]] = zhOrdered[k];
      }
      setState(() {
        for (var i = 0; i < zh.length; i++) {
          final idx = start + i;
          if (idx >= _items.length) break;
          if (_items[idx].url != urls[i]) continue;
          if (zh[i].isEmpty || zh[i] == titles[i]) continue;
          _items[idx] = _items[idx].copyWith(title: zh[i]);
          if (idx == _currentIndex &&
              (_titleText == titles[i] || _titleText.isEmpty)) {
            _titleText = zh[i];
          }
        }
      });
    } catch (_) {}
  }

  int _estimateBaseSpeed(int height) {
    if (height >= 1080) return 4500;
    if (height >= 720) return 2800;
    if (height >= 480) return 1500;
    if (height >= 360) return 900;
    return 600;
  }

  /// Drag/tap preview only — never touch the player (prevents snap-back).
  void _onSeekPreview(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final pos = (durMs * v).round();
    _sliderValue.value = v.clamp(0.0, 1.0);
    _currentTime.value =
        PlaybackHelpers.fmtDuration(Duration(milliseconds: pos));
  }

  /// Seek after drag/tap ends; keep [_seeking] until player position settles.
  Future<void> _onSeekCommit(double v) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _seeking = false;
      return;
    }
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) {
      _seeking = false;
      return;
    }
    final target = v.clamp(0.0, 1.0);
    final posMs = (durMs * target).round();
    _seeking = true;
    _sliderValue.value = target;
    _currentTime.value =
        PlaybackHelpers.fmtDuration(Duration(milliseconds: posMs));
    try {
      await c.seekTo(Duration(milliseconds: posMs));
      // Brief hold so progress timer doesn't overwrite with stale position
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || !identical(c, _controller)) return;
      final p = c.value.position;
      final d = c.value.duration;
      if (d.inMilliseconds > 0) {
        _sliderValue.value =
            (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        _currentTime.value = PlaybackHelpers.fmtDuration(p);
      }
    } catch (_) {
    } finally {
      if (mounted) _seeking = false;
    }
  }

  void _toggleMute() {
    _muted = !_muted;
    _controller?.setVolume(_muted ? 0 : 1);
    context.read<AppSettings>().setMuted(_muted);
    setState(() {});
  }

  void _fastForward() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final currentPos = c.value.position;
    final duration = c.value.duration;
    final newPos = currentPos + const Duration(seconds: 30);

    _seeking = true;
    if (newPos < duration) {
      c.seekTo(newPos).then((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _seeking = false;
          });
        }
      });
    } else {
      c.seekTo(duration).then((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _seeking = false;
          });
        }
      });
    }
  }

  void _openPlayerSettings() {
    final detail = _currentDetail;
    final heights = <int>[];
    if (detail != null) {
      for (final s in detail.streams) {
        if (s.height > 0) heights.add(s.height);
      }
    }
    showPlayerSettingsSheet(
      context,
      qualityHeights: heights.isEmpty ? null : heights,
      onQualityChanged: () {
        // Manual only: re-open current with new quality from settings.
        if (mounted) _playIndex(_currentIndex);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? '$_feedLabel暂无内容',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                  ),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _active = true;
                    _loadMore();
                  },
                  child: const Text('重新加载'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    showPlayerSettingsSheet(context);
                  },
                  child: const Text('打开网络代理设置',
                      style: TextStyle(color: Color(0xFFFF6B35))),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final immersive =
        context.select<PlayerChrome, bool>((c) => c.immersive);

    return PopScope(
      canPop: !immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && immersive) {
          context.read<PlayerChrome>().exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            final c = _controller;
            if (c == null || !c.value.isInitialized) return;
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
          },
          onLongPressStart: (_) => _controller?.setPlaybackSpeed(3.0),
          onLongPressEnd: (_) => _controller?.setPlaybackSpeed(1.0),
          child: VideoPlayerPage(
            items: _items,
            currentIndex: _currentIndex,
            controller: _controller,
            pageLoading: _pageLoading,
            muted: _muted,
            immersive: immersive,
            pageCtrl: _pageCtrl,
            sliderValue: _sliderValue,
            currentTime: _currentTime,
            totalTime: _totalTime,
            titleText: _titleText,
            speedLabel: _speedLabel,
            onPageChanged: _onPageChanged,
            onMute: _toggleMute,
            onFastForward: _fastForward,
            onFullscreen: _toggleFullscreen,
            onOpenSettings: _openPlayerSettings,
            onSeekPreview: _onSeekPreview,
            onSeekStart: () => _seeking = true,
            onSeekEnd: _onSeekCommit,
          ),
        ),
      ),
    );
  }

  /// Clean up detail cache that's far from current position to prevent memory growth
  void _cleanupDetailCache(int currentIndex) {
    const maxCacheDistance = 10;
    final toRemove = <int>[];
    for (final key in _detailCache.keys) {
      if ((key - currentIndex).abs() > maxCacheDistance) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      _detailCache.remove(key);
    }
  }
}
