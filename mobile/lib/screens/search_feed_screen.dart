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
import '../services/player_chrome.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';
import '../widgets/player_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which backend to use for detail / headers.
enum SearchSource { ph, x, zhong }

/// Vertical swipe player for search results.
/// Single active player + one silent pre-buffered next-video controller
/// (TikTok-style) for instant swipe; preloads next detail; can append pages via [onLoadMore].
class SearchFeedScreen extends StatefulWidget {
  const SearchFeedScreen({
    super.key,
    required this.items,
    required this.source,
    this.initialIndex = 0,
    this.title = '播放',
    this.onLoadMore,
  });

  final List<VideoItem> items;
  final SearchSource source;
  final int initialIndex;
  final String title;
  /// Returns newly appended items (may be empty when no more).
  final Future<List<VideoItem>> Function()? onLoadMore;

  @override
  State<SearchFeedScreen> createState() => _SearchFeedScreenState();
}

class _SearchFeedScreenState extends State<SearchFeedScreen>
    with WidgetsBindingObserver {
  late final PageController _pageCtrl;
  late final List<VideoItem> _items;
  late int _index;
  int _seq = 0;
  int _failStreak = 0;

  VideoPlayerController? _controller;
  bool _pageLoading = false;
  bool _loadingMore = false;
  bool _muted = false;
  bool _seeking = false;
  String _titleText = '';
  String _totalTime = '0:00';
  Timer? _progressTimer;
  Timer? _retryTimer;
  Timer? _skipTimer;
  final ValueNotifier<double> _slider = ValueNotifier(0);
  final ValueNotifier<String> _curTime = ValueNotifier('0:00');

  final Map<int, VideoDetail> _detailCache = {};
  int? _prefetchingIndex;
  VideoDetail? _currentDetail;
  PlayerChrome? _chrome;

  bool _showExitButton = false;
  double? _dragStartX;
  Duration? _dragStartPosition;
  Duration? _dragTargetPosition;
  String _seekPreviewText = '';

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

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  bool _wasLandscape = false;

  late final Map<String, String> _headers = _buildHeaders();

  Map<String, String> _buildHeaders() {
    switch (widget.source) {
      case SearchSource.x:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://www.xvideos.com/',
          'Origin': 'https://www.xvideos.com',
        };
      case SearchSource.zhong:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://mitaohk.com/',
          'Origin': 'https://mitaohk.com',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      case SearchSource.ph:
        return AppHttpHeaders.browser;
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
    _items = List<VideoItem>.from(widget.items);
    _index = widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _titleText = _items[_index].title;
    _startAccelerometerListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playIndex(_index));
  }

  @override
  void dispose() {
    try {
      _chrome?.ensurePortraitChrome();
    } catch (_) {}
    _accelSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _retryTimer?.cancel();
    _skipTimer?.cancel();
    _slider.dispose();
    _curTime.dispose();
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

      // 检测横屏：x 轴重力大于 y 轴（手机横置）
      final isLandscape = event.x.abs() > event.y.abs() && event.x.abs() > 6.0;

      if (isLandscape && !_wasLandscape && !chrome.immersive) {
        // 手机刚横置且当前是竖屏 → 自动进入横屏
        _wasLandscape = true;
        _toggleFullscreen();
      } else if (!isLandscape && _wasLandscape && chrome.immersive) {
        // 手机刚竖置且当前是横屏 → 自动退出横屏
        _wasLandscape = false;
        _toggleFullscreen();
      } else if (!isLandscape && !_wasLandscape) {
        _wasLandscape = false;
      } else if (isLandscape && _wasLandscape) {
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
    } else if (state == AppLifecycleState.resumed) {
      _controller?.play();
      WakelockPlus.enable();
    }
  }

  Future<VideoDetail> _fetchDetail(String url) {
    switch (widget.source) {
      case SearchSource.x:
        return context.read<XvideosApi>().getVideoDetail(url);
      case SearchSource.zhong:
        return context.read<MitaoApi>().getVideoDetail(url);
      case SearchSource.ph:
        return context.read<PhubApi>().getVideoDetail(url);
    }
  }

  Future<void> _ensureMoreIfNearEnd(int page) async {
    if (widget.onLoadMore == null) return;
    if (_loadingMore) return;
    if (page < _items.length - 3) return;
    _loadingMore = true;
    try {
      final extra = await widget.onLoadMore!();
      if (!mounted || extra.isEmpty) return;
      final seen = <String>{for (final e in _items) e.viewkey};
      final add = <VideoItem>[];
      for (final e in extra) {
        if (seen.add(e.viewkey)) add.add(e);
      }
      if (add.isEmpty) return;
      setState(() => _items.addAll(add));
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  final Set<int> _retried = {};

  void _scheduleSkipToNext(int fromIndex) {
    if (!_retried.contains(fromIndex)) {
      _retried.add(fromIndex);
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _playIndex(fromIndex);
      });
      return;
    }
    _failStreak++;
    if (_failStreak > 5) {
      _failStreak = 0;
      if (mounted) {
        PlaybackHelpers.toast(
          context,
          '连续多个视频无法播放，请检查网络或代理设置',
          duration: const Duration(seconds: 3),
        );
      }
      return;
    }
    if (mounted) PlaybackHelpers.toast(context, '已跳过无法播放的视频');
    final next = fromIndex + 1;
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (next >= _items.length) {
        await _ensureMoreIfNearEnd(_items.length - 1);
      }
      if (!mounted) return;
      if (next < _items.length) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(next);
        } else {
          _playIndex(next);
        }
      }
    });
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _items.length) return;
    final seq = ++_seq;
    final item = _items[index];

    // Check if we have this index preloaded in any slot
    VideoPlayerController? preloaded;
    VideoDetail? preloadDetail;
    int preloadSlot = 0; // 1, 2, or 3

    if (_preloadIndex == index &&
        _preloadController != null &&
        _preloadController!.value.isInitialized) {
      preloaded = _preloadController!;
      preloadDetail = _detailCache[index];
      preloadSlot = 1;
    } else if (_preloadIndex2 == index &&
        _preloadController2 != null &&
        _preloadController2!.value.isInitialized) {
      preloaded = _preloadController2!;
      preloadDetail = _detailCache[index];
      preloadSlot = 2;
    } else if (_preloadIndex3 == index &&
        _preloadController3 != null &&
        _preloadController3!.value.isInitialized) {
      preloaded = _preloadController3!;
      preloadDetail = _detailCache[index];
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

      await _disposePlayer(seqGuard: seq, exclude: preloaded);
      if (previous != null && !identical(previous, preloaded)) {
        try {
          await previous.pause();
        } catch (_) {}
        // ignore: unawaited_futures
        previous.dispose().catchError((_) {});
      }
      if (!mounted || seq != _seq) {
        try {
          await preloaded.dispose();
        } catch (_) {}
        return;
      }
      _failStreak = 0;
      _currentDetail = preloadDetail;
      _index = index;
      _muted = context.read<AppSettings>().muted;
      preloaded.setVolume(_muted ? 0 : 1);
      if (preloadDetail != null) {
        final skip = context.read<AppSettings>().skipIntro;
        final totalSec = preloaded.value.duration.inSeconds;
        if (totalSec >= 3000) {
          // >50min: jump to 1min
          try {
            await preloaded.seekTo(const Duration(seconds: 60));
          } catch (_) {}
        } else {
          await PlaybackHelpers.skipIntro(preloaded, enabled: skip);
        }
      }
      if (!mounted || seq != _seq) {
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
      });
      _slider.value = 0;
      _curTime.value = '0:00';
      // ignore: unawaited_futures
      _ensureMoreIfNearEnd(index);
      if (preloadDetail != null) {
        // ignore: unawaited_futures
        _translateTitleOnly(preloadDetail.title);
      }
      await preloaded.play();
      _startTimer();
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

    await _disposePlayer();
    if (!mounted || seq != _seq) return;

    setState(() {
      _pageLoading = true;
      _index = index;
      _titleText = item.title;
      _totalTime = '0:00';
    });
    _slider.value = 0;
    _curTime.value = '0:00';

    // Fire load-more early so swipe never dead-ends
    // ignore: unawaited_futures
    _ensureMoreIfNearEnd(index);

    VideoDetail detail;
    try {
      if (_detailCache.containsKey(index)) {
        detail = _detailCache[index]!;
      } else {
        detail = await _fetchDetail(item.url);
        _detailCache[index] = detail;
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() => _pageLoading = false);
        PlaybackHelpers.toast(
          context,
          '详情加载失败：${PlaybackHelpers.friendlyError(e)}',
        );
        _scheduleSkipToNext(index);
      }
      return;
    }
    if (!mounted || seq != _seq) return;

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

    // Start preloading next two videos immediately after detail is loaded
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

    final cap = context.read<AppSettings>().qualityCap;
    final stream =
        PlaybackHelpers.pickStream(detail, cap) ?? detail.bestStream;
    if (stream == null) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '无可用播放地址，已跳过');
      _scheduleSkipToNext(index);
      return;
    }
    _currentDetail = detail;

    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
    } catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      if (mounted && seq == _seq) {
        setState(() => _pageLoading = false);
        final net = context.read<AppSettings>();
        final tip = net.proxyEnabled && net.hasProxyEndpoint
            ? (net.proxyType == 'socks5'
                ? '列表可能已通，播放常不跟 SOCKS。可开 TUN 或改用 HTTP 代理'
                : '列表可能已通，播放仍失败。可开 TUN 或检查代理是否支持视频')
            : '播放失败。有列表播不动：开 TUN 或设置 HTTP 代理';
        PlaybackHelpers.toast(
          context,
          tip,
          duration: const Duration(seconds: 3),
        );
        _scheduleSkipToNext(index);
      }
      return;
    }
    if (!mounted || seq != _seq) {
      await player.dispose();
      return;
    }

    _failStreak = 0;
    _muted = context.read<AppSettings>().muted;
    player.setVolume(_muted ? 0 : 1);
    final skip = context.read<AppSettings>().skipIntro;

    // For videos >50min, skip to 1min mark instead of just the intro
    final totalSec = player.value.duration.inSeconds;
    if (totalSec >= 3000) {
      // >50min: jump to 1min (60s)
      try {
        await player.seekTo(const Duration(seconds: 60));
      } catch (_) {}
    } else {
      await PlaybackHelpers.skipIntro(player, enabled: skip);
    }

    if (!mounted || seq != _seq) {
      await player.dispose();
      return;
    }
    _controller = player;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = PlaybackHelpers.fmtDuration(player.value.duration);
    });
    // ignore: unawaited_futures
    _translateTitleOnly(detail.title);
    await player.play();
    _startTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});

    // Clean up old detail cache to prevent memory growth
    _cleanupDetailCache(index);
  }

  Future<void> _translateTitleOnly(String title) async {
    if (title.isEmpty) return;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) {
      if (mounted) setState(() => _titleText = title);
      return;
    }
    try {
      final zh = await context.read<Translator>().enToZh(title);
      if (!mounted || zh.isEmpty) return;
      setState(() => _titleText = zh);
      final i = _index;
      if (i >= 0 && i < _items.length && _items[i].title == title) {
        _items[i] = _items[i].copyWith(title: zh);
      }
    } catch (_) {}
  }

  Future<void> _prefetchDetail(int index) async {
    if (index < 0 || index >= _items.length) return;
    if (_detailCache.containsKey(index)) return;
    if (_prefetchingIndex == index) return;
    _prefetchingIndex = index;
    final url = _items[index].url;
    try {
      final d = await _fetchDetail(url);
      if (!mounted) return;
      _detailCache[index] = d;
      _detailCache.removeWhere((k, _) => (k - _index).abs() > 3);
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
    if (index < 0 || index >= _items.length || index == _index) return;
    if (_preloadIndex == index && _preloadController != null) return;
    final seq = _seq;
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
    if (seq != _seq) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries < 2 && seq == _seq) {
        _preloadRetries++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries));
        if (seq == _seq && mounted) {
          return _preloadNext(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _seq || !mounted) {
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
    if (index < 0 || index >= _items.length || index == _index) return;
    if (_preloadIndex2 == index && _preloadController2 != null) return;
    final seq = _seq;
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
    if (seq != _seq) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries2 = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries2 < 2 && seq == _seq) {
        _preloadRetries2++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries2));
        if (seq == _seq && mounted) {
          return _preloadNext2(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _seq || !mounted) {
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
    if (index < 0 || index >= _items.length || index == _index) return;
    if (_preloadIndex3 == index && _preloadController3 != null) return;
    final seq = _seq;
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
    if (seq != _seq) return;
    final player = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await player.initialize();
      _preloadRetries3 = 0;
    } catch (e) {
      // Retry up to 2 times for transient failures
      if (_preloadRetries3 < 2 && seq == _seq) {
        _preloadRetries3++;
        try {
          await player.dispose();
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 300 * _preloadRetries3));
        if (seq == _seq && mounted) {
          return _preloadNext3(index);
        }
      }
      try {
        await player.dispose();
      } catch (_) {}
      return;
    }
    if (seq != _seq || !mounted) {
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

  Future<void> _disposePlayer({int? seqGuard, VideoPlayerController? exclude}) async {
    _progressTimer?.cancel();
    _progressTimer = null;
    final c = _controller;
    _controller = null;
    if (c == null || identical(c, exclude)) return;
    if (seqGuard != null && seqGuard != _seq) return;
    try {
      await c.pause();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  void _startTimer() {
    final ctrl = _controller;
    if (ctrl == null) return;
    _progressTimer?.cancel();
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
      _slider.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _curTime.value = PlaybackHelpers.fmtDuration(pos);
      final t = PlaybackHelpers.fmtDuration(dur);
      if (t != _totalTime && mounted) setState(() => _totalTime = t);
    });
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
        if (mounted) _playIndex(_index);
      },
    );
  }

  void _onPageChanged(int page) {
    if (page == _index) return;
    _retried.removeWhere((i) => (i - page).abs() > 3);
    _playIndex(page);
    // ignore: unawaited_futures
    _ensureMoreIfNearEnd(page);
  }

  void _onSeekPreview(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final ms = (durMs * v).round();
    _slider.value = v.clamp(0.0, 1.0);
    _curTime.value = PlaybackHelpers.fmtDuration(Duration(milliseconds: ms));
  }

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
    final ms = (durMs * target).round();
    _seeking = true;
    _slider.value = target;
    _curTime.value = PlaybackHelpers.fmtDuration(Duration(milliseconds: ms));
    try {
      await c.seekTo(Duration(milliseconds: ms));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || !identical(c, _controller)) return;
      final p = c.value.position;
      final d = c.value.duration;
      if (d.inMilliseconds > 0) {
        _slider.value = (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        _curTime.value = PlaybackHelpers.fmtDuration(p);
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

  void _onHorizontalDragStart(DragStartDetails details) {
    final chrome = _chrome;
    if (chrome == null || !chrome.immersive) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    setState(() {
      _dragStartX = details.globalPosition.dx;
      _dragStartPosition = ctrl.value.position;
      _seekPreviewText = '';
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final chrome = _chrome;
    if (chrome == null || !chrome.immersive || _dragStartX == null || _dragStartPosition == null) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final deltaX = details.globalPosition.dx - _dragStartX!;
    final screenWidth = MediaQuery.of(context).size.width;

    final secondsPerScreenWidth = 360.0;
    final deltaSec = (deltaX / screenWidth * secondsPerScreenWidth).round();

    final newPos = _dragStartPosition! + Duration(seconds: deltaSec);
    final duration = ctrl.value.duration;
    final clampedPos = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, duration.inMilliseconds),
    );

    String formatTime(Duration d) {
      final min = d.inMinutes;
      final sec = d.inSeconds % 60;
      return '$min:${sec.toString().padLeft(2, '0')}';
    }

    setState(() {
      _dragTargetPosition = clampedPos;
      if (deltaSec > 0) {
        _seekPreviewText = '+${deltaSec}秒 → ${formatTime(clampedPos)}';
      } else if (deltaSec < 0) {
        _seekPreviewText = '${deltaSec}秒 → ${formatTime(clampedPos)}';
      } else {
        _seekPreviewText = formatTime(clampedPos);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final chrome = _chrome;
    if (chrome == null || !chrome.immersive || _dragStartX == null || _dragStartPosition == null) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    // 使用 Update 中计算好的目标位置
    final targetPos = _dragTargetPosition ?? _dragStartPosition!;
    ctrl.seekTo(targetPos);

    setState(() {
      _dragStartX = null;
      _dragStartPosition = null;
      _dragTargetPosition = null;
      _seekPreviewText = '';
    });
  }

  void _onTapScreen() {
    final chrome = _chrome;
    if (chrome == null || !chrome.immersive) return;
    setState(() {
      _showExitButton = !_showExitButton;
    });

    if (_showExitButton) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showExitButton) {
          setState(() {
            _showExitButton = false;
          });
        }
      });
    }
  }


  @override
  Widget build(BuildContext context) {
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
        extendBodyBehindAppBar: true,
        appBar: immersive
            ? null
            : AppBar(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(widget.title, style: const TextStyle(fontSize: 16)),
              ),
        body: GestureDetector(
          onTap: () {
            if (_chrome?.immersive == true) {
              _onTapScreen();
            } else {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return;
              if (c.value.isPlaying) {
                c.pause();
              } else {
                c.play();
              }
            }
          },
          onLongPressStart: (_) => _controller?.setPlaybackSpeed(3.0),
          onLongPressEnd: (_) => _controller?.setPlaybackSpeed(1.0),
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.vertical,
                itemCount: _items.length,
                onPageChanged: _onPageChanged,
                physics: _dragStartX != null ? const NeverScrollableScrollPhysics() : null,
                itemBuilder: (_, i) {
                  if (i == _index &&
                      _controller != null &&
                      _controller!.value.isInitialized) {
                    return ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    );
                  }
                  final thumb = _items[i].thumb;
                  return Container(
                    color: const Color(0xFF1A1A1A),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb != null && thumb.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: thumb,
                            httpHeaders: AppHttpHeaders.forMediaUrl(thumb),
                            fit: BoxFit.cover,
                            memCacheWidth: 720,
                            placeholder: (_, __) =>
                                const ColoredBox(color: Color(0xFF1A1A1A)),
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        if (i == _index && _pageLoading)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B35),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              // 横屏手势进度预览
              if (immersive && _seekPreviewText.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _seekPreviewText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (immersive) ...[
                // 横屏：点击屏幕显示/隐藏控制栏
                if (_showExitButton) ...[
                  // 退出按钮
                  Positioned(
                    right: 16,
                    top: 16,
                    child: SafeArea(
                      child: GestureDetector(
                        onTap: _toggleFullscreen,
                        child: Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white.withOpacity(0.5),
                          size: 28,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 设置按钮
                  Positioned(
                    left: 16,
                    top: 16,
                    child: SafeArea(
                      child: GestureDetector(
                        onTap: () {
                          showPlayerSettingsSheet(
                            context,
                            onQualityChanged: () {
                              // 搜索页暂不响应画质更改
                            },
                            onProxyChanged: () {
                              // 搜索页暂不响应代理更改
                            },
                          );
                        },
                        child: Icon(
                          Icons.settings,
                          color: Colors.white.withOpacity(0.5),
                          size: 28,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 进度条
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: FeedProgressBar(
                        slider: _slider,
                        curTime: _curTime,
                        totalTime: _totalTime,
                        onChanged: _onSeekPreview,
                        onChangeStart: (_) {
                          _seeking = true;
                        },
                        onChangeEnd: (v) {
                          // ignore: unawaited_futures
                          _onSeekCommit(v);
                        },
                      ),
                    ),
                  ),
                ],
              ] else ...[
                Positioned(
                  left: 12,
                  right: 56,
                  top: 8,
                  child: SafeArea(
                    child: Text(
                      _titleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4)
                        ],
                      ),
                    ),
                  ),
                ),
                // 竖屏：全屏按钮（半透明，无背景）
                Positioned(
                  left: 10,
                  top: 8,
                  child: SafeArea(
                    child: _MinimalButton(
                      storageKey: 'search_fullscreen_button_normal',
                      defaultOffset: const Offset(10, 8),
                      icon: Icons.fullscreen,
                      onTap: _toggleFullscreen,
                    ),
                  ),
                ),
                // 竖屏：设置按钮（半透明，无背景）
                Positioned(
                  right: 10,
                  top: 8,
                  child: SafeArea(
                    child: _MinimalButton(
                      storageKey: 'search_settings_button_normal',
                      defaultOffset: const Offset(10, 8),
                      icon: Icons.settings,
                      onTap: () {
                        showPlayerSettingsSheet(
                          context,
                          onQualityChanged: () {
                            // 搜索页暂不响应画质更改
                          },
                          onProxyChanged: () {
                            // 搜索页暂不响应代理更改
                          },
                        );
                      },
                    ),
                  ),
                ),
                // 竖屏：快进按钮（半透明，无背景）
                Positioned(
                  left: 10,
                  bottom: 80,
                  child: SafeArea(
                    child: _MinimalButton(
                      storageKey: 'search_fastforward_button_normal',
                      defaultOffset: const Offset(10, 80),
                      icon: Icons.forward_30,
                      onTap: _fastForward,
                    ),
                  ),
                ),
                // 竖屏：音量按钮（半透明，无背景）
                Positioned(
                  right: 10,
                  bottom: 80,
                  child: SafeArea(
                    child: _MinimalButton(
                      storageKey: 'search_mute_button_normal',
                      defaultOffset: const Offset(10, 80),
                      icon: _muted ? Icons.volume_off : Icons.volume_up,
                      onTap: _toggleMute,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: FeedProgressBar(
                      slider: _slider,
                      curTime: _curTime,
                      totalTime: _totalTime,
                      onChanged: _onSeekPreview,
                      onChangeStart: (_) {
                        _seeking = true;
                      },
                      onChangeEnd: (v) {
                        // ignore: unawaited_futures
                        _onSeekCommit(v);
                      },
                    ),
                  ),
                ),
              ],
            ],
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

/// 极简按钮：半透明图标，无背景，支持长按拖动
class _MinimalButton extends StatefulWidget {
  const _MinimalButton({
    required this.storageKey,
    required this.defaultOffset,
    required this.icon,
    required this.onTap,
  });

  final String storageKey;
  final Offset defaultOffset;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MinimalButton> createState() => _MinimalButtonState();
}

class _MinimalButtonState extends State<_MinimalButton> {
  Offset? _savedOffset;
  bool _isDragging = false;
  Offset _currentDragOffset = Offset.zero;
  Offset _dragStartOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadOffset();
  }

  Future<void> _loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('${widget.storageKey}_offset_x');
    final y = prefs.getDouble('${widget.storageKey}_offset_y');
    if (x != null && y != null && mounted) {
      setState(() {
        _savedOffset = Offset(x, y);
      });
    }
  }

  Future<void> _saveOffset(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${widget.storageKey}_offset_x', offset.dx);
    await prefs.setDouble('${widget.storageKey}_offset_y', offset.dy);
  }

  @override
  Widget build(BuildContext context) {
    final displayOffset = _isDragging
        ? _currentDragOffset
        : (_savedOffset ?? Offset.zero);

    return Transform.translate(
      offset: displayOffset,
      child: GestureDetector(
        onTap: _isDragging ? null : widget.onTap,
        onLongPressStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartOffset = _savedOffset ?? Offset.zero;
            _currentDragOffset = _dragStartOffset;
          });
        },
        onLongPressMoveUpdate: (details) {
          if (!_isDragging) return;
          setState(() {
            _currentDragOffset = _dragStartOffset + details.offsetFromOrigin;
            final size = MediaQuery.of(context).size;
            final padding = MediaQuery.of(context).padding;
            _currentDragOffset = Offset(
              _currentDragOffset.dx.clamp(
                -widget.defaultOffset.dx,
                size.width - widget.defaultOffset.dx - 40 - padding.right,
              ),
              _currentDragOffset.dy.clamp(
                -widget.defaultOffset.dy,
                size.height - widget.defaultOffset.dy - 40 - padding.bottom,
              ),
            );
          });
        },
        onLongPressEnd: (details) {
          setState(() {
            _savedOffset = _currentDragOffset;
            _isDragging = false;
          });
          _saveOffset(_currentDragOffset);
        },
        child: AnimatedScale(
          scale: _isDragging ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Icon(
            widget.icon,
            color: _isDragging
                ? Colors.white.withOpacity(0.9)
                : Colors.white.withOpacity(0.5),
            size: 28,
            shadows: const [
              Shadow(color: Colors.black45, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}
