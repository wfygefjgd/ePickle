import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';

/// Shared playback helpers for feed / search-feed.
class PlaybackHelpers {
  /// Skip intro ads based on video duration:
  /// - < 100s: skip 10s
  /// - 100s - 10min: skip 15s
  /// - 10min - 15min: skip 25s
  /// - 15min - 50min: skip 40s
  /// - > 50min: skip 70s
  /// Never skip short clips (trailers / broken 9s teasers).
  static Future<void> skipIntro(
    VideoPlayerController ctrl, {
    bool enabled = true,
    int fallbackDurationSec = 0,
  }) async {
    if (!enabled || !ctrl.value.isInitialized) return;
    var total = ctrl.value.duration.inSeconds;
    if (total <= 0 && fallbackDurationSec > 0) {
      total = fallbackDurationSec;
    }
    // Short / unknown: do not seek (avoids killing 9s teasers or live)
    if (total > 0 && total < 45) return;
    if (total <= 0) return;

    int skipSeconds;
    if (total < 100) {
      skipSeconds = 10;
    } else if (total < 600) {
      skipSeconds = 15;
    } else if (total < 900) {
      skipSeconds = 25;
    } else if (total < 3000) {
      skipSeconds = 40;
    } else {
      skipSeconds = 70;
    }

    if (total - skipSeconds < 5) return;

    try {
      await ctrl.seekTo(Duration(seconds: skipSeconds));
    } catch (_) {}
  }

  /// Effective duration for progress UI: player first, then detail metadata.
  static Duration effectiveDuration(
    VideoPlayerController ctrl, {
    int fallbackSec = 0,
  }) {
    final d = ctrl.value.duration;
    if (d.inMilliseconds > 500) return d;
    if (fallbackSec > 0) return Duration(seconds: fallbackSec);
    return d;
  }

  static StreamQuality? pickStream(VideoDetail detail, int qualityCap) =>
      detail.streamForCap(qualityCap);

  /// Ordered candidates for init fallback: preferred/cap first, then lower, then higher.
  static List<StreamQuality> streamCandidates(
    VideoDetail detail,
    int qualityCap,
  ) {
    if (detail.streams.isEmpty) return const [];
    final primary = detail.streamForCap(qualityCap);
    final rest = [...detail.streams]
      ..sort((a, b) => b.pixels.compareTo(a.pixels));
    final out = <StreamQuality>[];
    final seen = <String>{};
    void add(StreamQuality? s) {
      if (s == null || s.url.isEmpty) return;
      if (seen.add(s.url)) out.add(s);
    }

    add(primary);
    // Lower first (more likely to play on weak net), then any remaining.
    final lower = rest
        .where((s) =>
            primary == null || s.height <= 0 || s.height < primary.height)
        .toList()
      ..sort((a, b) => b.pixels.compareTo(a.pixels));
    for (final s in lower) {
      add(s);
    }
    for (final s in rest) {
      add(s);
    }
    return out;
  }

  /// Reject hover/ad/fallback clips that initialize successfully but are far
  /// shorter than the real VOD. Several sites return a valid 9-60 second MP4
  /// when their protected full-stream request was not authorized.
  static bool isLikelyPreview(
    VideoPlayerController controller,
    VideoDetail detail, {
    String? siteId,
    bool isLive = false,
  }) {
    if (isLive || !controller.value.isInitialized) return false;
    final seconds = controller.value.duration.inSeconds;
    if (seconds <= 0) return false;
    if (detail.durationSec >= 120 &&
        seconds < 90 &&
        seconds * 4 < detail.durationSec) {
      return true;
    }
    const longFormSites = {
      'eporner',
      'redtube',
      '7mmtv',
      'our55',
      'xqq88',
      'javmix',
      'javgg',
      'bestjavporn',
    };
    return longFormSites.contains(siteId) && seconds <= 75;
  }

  /// Brief non-blocking toast.
  static void toast(
    BuildContext context,
    String msg, {
    Duration duration = const Duration(milliseconds: 1200),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  /// Map raw exceptions to short Chinese hints (keep original if unknown).
  static String friendlyError(Object error) {
    final s = error.toString();
    final low = s.toLowerCase();
    String core;
    if (s.contains('PhubException:')) {
      core = s.replaceFirst('PhubException: ', '');
    } else if (low.contains('403') || low.contains('forbidden')) {
      core = '访问被拒绝(403)';
    } else if (low.contains('404') || low.contains('not found')) {
      core = '内容不存在(404)';
    } else if (low.contains('timeout') || low.contains('timed out')) {
      core = '网络超时';
    } else if (low.contains('socket') ||
        low.contains('connection') ||
        low.contains('network') ||
        low.contains('failed host lookup') ||
        low.contains('connection refused') ||
        low.contains('proxy')) {
      core = '网络异常 / 代理不可达';
    } else if (low.contains('handshake') || low.contains('certificate')) {
      core = '安全连接失败';
    } else if (s.length > 80) {
      core = '${s.substring(0, 80)}…';
    } else {
      core = s;
    }
    if (low.contains('结构不匹配') ||
        low.contains('解析不到') ||
        low.contains('结构可能已改版')) {
      return '$core\n\n该频道适配器需要更新；这不是普通代理错误。';
    }
    if (low.contains('403') ||
        low.contains('forbidden') ||
        low.contains('cloudflare') ||
        low.contains('cookie') ||
        low.contains('验证页')) {
      return '$core\n\n站点拒绝了当前请求或要求浏览器验证，可切换网络/TUN 后重试。';
    }
    if (low.contains('failed host lookup') ||
        low.contains('name not resolved') ||
        low.contains('dns')) {
      return '$core\n\n域名无法解析；请检查 DNS、网络或该镜像是否已失效。';
    }
    return '$core\n\n'
        '可尝试：设置 → 网络代理 → 重新检测系统代理，或启用 TUN / 系统 VPN。';
  }

  static String fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Circular side control — fixed size so a column of buttons shares one center line.
class FeedCircleButton extends StatelessWidget {
  const FeedCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  static const double box = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: box,
      height: box,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }
}

/// Side controls: fast forward (left) + mute (right), same horizontal line.
/// Fullscreen lives under the title on the left.
class FeedSideControls extends StatelessWidget {
  const FeedSideControls({
    super.key,
    required this.muted,
    required this.onMute,
    required this.onFastForward,
  });

  final bool muted;
  final VoidCallback onMute;
  final VoidCallback onFastForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FeedCircleButton(
          icon: Icons.forward_30,
          onTap: onFastForward,
          size: 24,
        ),
        const SizedBox(width: 8),
        FeedCircleButton(
          icon: muted ? Icons.volume_off : Icons.volume_up,
          onTap: onMute,
          size: 24,
        ),
      ],
    );
  }
}

/// Bottom seek bar; drag only updates UI — parent seeks on [onChangeEnd].
class FeedProgressBar extends StatelessWidget {
  const FeedProgressBar({
    super.key,
    required this.slider,
    required this.curTime,
    required this.totalTime,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final ValueNotifier<double> slider;
  final ValueNotifier<String> curTime;
  final String totalTime;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ValueListenableBuilder<String>(
            valueListenable: curTime,
            builder: (_, t, __) => Text(
              t,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFFF6B35),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFF6B35),
                // Smoother visual while dragging
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: ValueListenableBuilder<double>(
                valueListenable: slider,
                builder: (_, v, __) => Slider(
                  value: v.clamp(0.0, 1.0),
                  onChanged: onChanged,
                  onChangeStart: onChangeStart,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ),
          Text(
            totalTime,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
