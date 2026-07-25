import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';

class VideoPlayerPage extends StatelessWidget {
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

  final ValueChanged<int> onPageChanged;
  final VoidCallback onMute;
  final VoidCallback onFastForward;
  final VoidCallback onFullscreen;
  final VoidCallback onOpenSettings;
  final ValueChanged<double> onSeekPreview;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: pageCtrl,
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          onPageChanged: onPageChanged,
          itemBuilder: (_, i) {
            if (i == currentIndex &&
                controller != null &&
                controller!.value.isInitialized) {
              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller!),
                  ),
                ),
              );
            }
            final thumb = items[i].thumb;
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
                  if (i == currentIndex && pageLoading)
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
        if (immersive) ...[
          // 固定位置的设置按钮
          Positioned(
            left: 8,
            top: 8,
            child: SafeArea(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: '设置 / 画质',
                  icon: const Icon(Icons.tune, color: Colors.white70, size: 20),
                  onPressed: onOpenSettings,
                ),
              ),
            ),
          ),
          // 固定位置的全屏按钮
          Positioned(
            right: 8,
            top: 8,
            child: SafeArea(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: '退出全屏',
                  icon: const Icon(Icons.fullscreen_exit,
                      color: Colors.white70, size: 22),
                  onPressed: onFullscreen,
                ),
              ),
            ),
          ),
          // 可拖动的快进按钮
          if (controller != null || pageLoading)
            _DraggableFastForward(
              onTap: onFastForward,
            ),
          // 固定位置的音量按钮
          if (controller != null || pageLoading)
            Positioned(
              right: 8,
              bottom: 80,
              child: SafeArea(
                child: FeedCircleButton(
                  icon: muted ? Icons.volume_off : Icons.volume_up,
                  onTap: onMute,
                  size: 24,
                ),
              ),
            ),
        ] else if (controller != null || pageLoading) ...[
          _buildTopBar(),
          // 固定位置的全屏按钮
          Positioned(
            left: 10,
            top: 80,
            child: SafeArea(
              child: FeedCircleButton(
                icon: Icons.fullscreen,
                onTap: onFullscreen,
              ),
            ),
          ),
          // 固定位置的设置按钮
          Positioned(
            right: 10,
            top: 80,
            child: SafeArea(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: '设置',
                  icon:
                      const Icon(Icons.tune, color: Colors.white70, size: 20),
                  onPressed: onOpenSettings,
                ),
              ),
            ),
          ),
          // 可拖动的快进按钮
          _DraggableFastForward(
            onTap: onFastForward,
          ),
          // 固定位置的音量按钮
          Positioned(
            right: 10,
            bottom: 80,
            child: SafeArea(
              child: FeedCircleButton(
                icon: muted ? Icons.volume_off : Icons.volume_up,
                onTap: onMute,
                size: 24,
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
                  slider: sliderValue,
                  curTime: currentTime,
                  totalTime: totalTime,
                  onChanged: onSeekPreview,
                  onChangeStart: (_) => onSeekStart(),
                  onChangeEnd: onSeekEnd,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    final title = titleText.isNotEmpty
        ? titleText
        : (currentIndex < items.length ? items[currentIndex].title : '');
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
            if (speedLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  speedLabel,
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

/// 可拖动的快进按钮
class _DraggableFastForward extends StatefulWidget {
  const _DraggableFastForward({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DraggableFastForward> createState() => _DraggableFastForwardState();
}

class _DraggableFastForwardState extends State<_DraggableFastForward> {
  Offset _position = const Offset(10, 500);
  bool _isDragging = false;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('fastforward_x') ?? 10.0;
    final y = prefs.getDouble('fastforward_y') ?? 500.0;
    if (mounted) {
      setState(() {
        _position = Offset(x, y);
      });
    }
  }

  Future<void> _savePosition(Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fastforward_x', pos.dx);
    await prefs.setDouble('fastforward_y', pos.dy);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStart = details.globalPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, size.width - 48),
              (_position.dy + details.delta.dy).clamp(0.0, size.height - 48),
            );
          });
        },
        onPanEnd: (details) {
          final totalDrag = _dragStart == null
              ? 0.0
              : (details.velocity.pixelsPerSecond.distance);

          setState(() {
            _isDragging = false;
          });

          _savePosition(_position);

          // 如果几乎没移动，触发点击
          if (totalDrag < 50) {
            widget.onTap();
          }
        },
        child: SafeArea(
          child: FeedCircleButton(
            icon: Icons.forward_30,
            onTap: _isDragging ? () {} : widget.onTap,
            size: 24,
          ),
        ),
      ),
    );
  }
}
