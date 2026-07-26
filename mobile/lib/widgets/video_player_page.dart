import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';
import 'stripchat_live_view.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.controller,
    required this.pageLoading,
    required this.muted,
    required this.immersive,
    required this.pageCtrl,
    required this.sliderValue,
    required this.currentTime,
    required this.totalTime,
    required this.titleText,
    required this.speedLabel,
    this.browserLiveUrl,
    required this.onPageChanged,
    required this.onMute,
    required this.onFastForward,
    required this.onFullscreen,
    required this.onOpenSettings,
    required this.onSeekPreview,
    required this.onSeekStart,
    required this.onSeekEnd,
  });

  final List<VideoItem> items;
  final int currentIndex;
  final VideoPlayerController? controller;
  final bool pageLoading;
  final bool muted;
  final bool immersive;
  final PageController pageCtrl;
  final ValueNotifier<double> sliderValue;
  final ValueNotifier<String> currentTime;
  final String totalTime;
  final String titleText;
  final String speedLabel;
  final String? browserLiveUrl;

  final ValueChanged<int> onPageChanged;
  final VoidCallback onMute;
  final VoidCallback onFastForward;
  final VoidCallback onFullscreen;
  final VoidCallback onOpenSettings;
  final ValueChanged<double> onSeekPreview;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekEnd;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  bool _showExitButton = false;
  double? _dragStartX;
  Duration? _dragStartPosition;
  Duration? _dragTargetPosition;
  String _seekPreviewText = '';

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.immersive) return;
    final ctrl = widget.controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    widget.onSeekStart();
    setState(() {
      _dragStartX = details.globalPosition.dx;
      _dragStartPosition = ctrl.value.position;
      _seekPreviewText = '';
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.immersive ||
        _dragStartX == null ||
        _dragStartPosition == null) {
      return;
    }
    final ctrl = widget.controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final deltaX = details.globalPosition.dx - _dragStartX!;
    final screenWidth = MediaQuery.of(context).size.width;

    // 距离映射：拖动屏幕 1/6 宽度 = 60秒
    final secondsPerScreenWidth = 360.0; // 全屏宽度 = 6分钟
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
        _seekPreviewText = '+$deltaSec秒 → ${formatTime(clampedPos)}';
      } else if (deltaSec < 0) {
        _seekPreviewText = '$deltaSec秒 → ${formatTime(clampedPos)}';
      } else {
        _seekPreviewText = formatTime(clampedPos);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.immersive ||
        _dragStartX == null ||
        _dragStartPosition == null) {
      return;
    }
    final ctrl = widget.controller;
    final targetPos = _dragTargetPosition ?? _dragStartPosition!;
    setState(() {
      _dragStartX = null;
      _dragStartPosition = null;
      _dragTargetPosition = null;
      _seekPreviewText = '';
    });
    if (ctrl == null || !ctrl.value.isInitialized) {
      // Clear parent _seeking (onSeekStart already set it).
      widget.onSeekEnd(
        widget.sliderValue.value.clamp(0.0, 1.0),
      );
      return;
    }

    final durMs = ctrl.value.duration.inMilliseconds;
    final ratio =
        durMs > 0 ? (targetPos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0;
    // Commit via parent so progress timer / stall arm stay in sync.
    widget.onSeekEnd(ratio);
  }

  void _togglePlayPause() {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
  }

  void _onTapScreen() {
    if (widget.immersive) {
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
      return;
    }
    // Portrait: single tap toggles play/pause.
    _togglePlayPause();
  }

  void _onDoubleTapScreen() {
    // Double-tap always toggles play/pause (portrait + landscape).
    _togglePlayPause();
  }

  Widget _buildActivePlayer() {
    final browserLiveUrl = widget.browserLiveUrl;
    if (browserLiveUrl != null && browserLiveUrl.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: StripchatLiveView(
          roomUrl: browserLiveUrl,
          muted: widget.muted,
        ),
      );
    }
    final c = widget.controller;
    if (c != null && c.value.isInitialized) {
      final ar = c.value.aspectRatio;
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: (ar.isFinite && ar > 0.05) ? ar : (16 / 9),
            child: VideoPlayer(c),
          ),
        ),
      );
    }
    final i = widget.currentIndex;
    final thumb =
        (i >= 0 && i < widget.items.length) ? widget.items[i].thumb : null;
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
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (widget.pageLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            ),
        ],
      ),
    );
  }

  /// Portrait: vertical PageView. Landscape: single surface only.
  /// RotatedBox changes viewport height; PageView pixel offset then maps to
  /// page 0 → first video thumb while audio stays on the real controller.
  Widget _buildVideoSurface() {
    if (widget.immersive) {
      return _buildActivePlayer();
    }
    return PageView.builder(
      controller: widget.pageCtrl,
      scrollDirection: Axis.vertical,
      itemCount: widget.items.length,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (_, i) {
        if (i == widget.currentIndex &&
            (widget.browserLiveUrl != null ||
                (widget.controller != null &&
                    widget.controller!.value.isInitialized))) {
          return _buildActivePlayer();
        }
        final thumb = widget.items[i].thumb;
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
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              if (i == widget.currentIndex && widget.pageLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF6B35),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _onTapScreen,
          onDoubleTap: _onDoubleTapScreen,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: _buildVideoSurface(),
        ),
        // 横屏手势进度预览
        if (widget.immersive && _seekPreviewText.isNotEmpty)
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
        if (widget.immersive) ...[
          // 横屏：点击屏幕显示/隐藏控制栏
          if (_showExitButton) ...[
            // 退出按钮
            Positioned(
              right: 16,
              top: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: widget.onFullscreen,
                  child: Icon(
                    Icons.fullscreen_exit,
                    color: Colors.white.withValues(alpha: 0.5),
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
                  onTap: widget.onOpenSettings,
                  child: Icon(
                    Icons.settings,
                    color: Colors.white.withValues(alpha: 0.5),
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
                child: RepaintBoundary(
                  child: FeedProgressBar(
                    slider: widget.sliderValue,
                    curTime: widget.currentTime,
                    totalTime: widget.totalTime,
                    onChanged: widget.onSeekPreview,
                    onChangeStart: (_) => widget.onSeekStart(),
                    onChangeEnd: widget.onSeekEnd,
                  ),
                ),
              ),
            ),
          ],
        ] else ...[
          _buildTopBar(),
          // 竖屏：全屏按钮（半透明，无背景）
          Positioned(
            left: 10,
            top: 8,
            child: SafeArea(
              child: _MinimalButton(
                storageKey: 'fullscreen_button_normal',
                defaultOffset: const Offset(10, 8),
                icon: Icons.fullscreen,
                onTap: widget.onFullscreen,
              ),
            ),
          ),
          // 竖屏：设置按钮（半透明，无背景）
          Positioned(
            right: 10,
            top: 8,
            child: SafeArea(
              child: _MinimalButton(
                storageKey: 'settings_button_normal',
                defaultOffset: const Offset(10, 8),
                icon: Icons.settings,
                onTap: widget.onOpenSettings,
              ),
            ),
          ),
          // 竖屏：快进按钮（半透明，无背景）
          Positioned(
            left: 10,
            bottom: 80,
            child: SafeArea(
              child: _MinimalButton(
                storageKey: 'fastforward_button_normal',
                defaultOffset: const Offset(10, 80),
                icon: Icons.forward_30,
                onTap: widget.onFastForward,
              ),
            ),
          ),
          // 竖屏：音量按钮（半透明，无背景）
          Positioned(
            right: 10,
            bottom: 80,
            child: SafeArea(
              child: _MinimalButton(
                storageKey: 'mute_button_normal',
                defaultOffset: const Offset(10, 80),
                icon: widget.muted ? Icons.volume_off : Icons.volume_up,
                onTap: widget.onMute,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: RepaintBoundary(
                child: FeedProgressBar(
                  slider: widget.sliderValue,
                  curTime: widget.currentTime,
                  totalTime: widget.totalTime,
                  onChanged: widget.onSeekPreview,
                  onChangeStart: (_) => widget.onSeekStart(),
                  onChangeEnd: widget.onSeekEnd,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    final title = widget.titleText.isNotEmpty
        ? widget.titleText
        : (widget.currentIndex < widget.items.length
            ? widget.items[widget.currentIndex].title
            : '');
    return Positioned(
      left: 10,
      right: 10,
      top: 8,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
            ),
            if (widget.speedLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.speedLabel,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
    final displayOffset =
        _isDragging ? _currentDragOffset : (_savedOffset ?? Offset.zero);

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
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.5),
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
