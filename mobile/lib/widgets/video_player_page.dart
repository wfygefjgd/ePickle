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
          // 可拖动的设置按钮
          _DraggableButton(
            storageKey: 'settings_button',
            defaultPosition: const Offset(8, 8),
            icon: Icons.tune,
            tooltip: '设置 / 画质',
            onTap: onOpenSettings,
          ),
          // 可拖动的全屏按钮
          _DraggableButton(
            storageKey: 'fullscreen_button',
            defaultPosition: Offset(MediaQuery.of(context).size.width - 56, 8),
            icon: Icons.fullscreen_exit,
            tooltip: '退出全屏',
            onTap: onFullscreen,
          ),
          // 可拖动的快进按钮
          if (controller != null || pageLoading)
            _DraggableFastForward(
              onTap: onFastForward,
            ),
          // 可拖动的音量按钮
          if (controller != null || pageLoading)
            _DraggableButton(
              storageKey: 'mute_button_immersive',
              defaultPosition: Offset(MediaQuery.of(context).size.width - 56, MediaQuery.of(context).size.height - 128),
              icon: muted ? Icons.volume_off : Icons.volume_up,
              tooltip: '音量',
              onTap: onMute,
            ),
        ] else if (controller != null || pageLoading) ...[
          _buildTopBar(),
          // 可拖动的全屏按钮（左上角）
          _DraggableButton(
            storageKey: 'fullscreen_button_normal',
            defaultPosition: const Offset(10, 8),
            icon: Icons.fullscreen,
            tooltip: '全屏',
            onTap: onFullscreen,
          ),
          // 可拖动的设置按钮（右上角）
          _DraggableButton(
            storageKey: 'settings_button_normal',
            defaultPosition: Offset(MediaQuery.of(context).size.width - 56, 8),
            icon: Icons.tune,
            tooltip: '设置',
            onTap: onOpenSettings,
          ),
          // 可拖动的快进按钮
          _DraggableFastForward(
            onTap: onFastForward,
          ),
          // 可拖动的音量按钮
          _DraggableButton(
            storageKey: 'mute_button_normal',
            defaultPosition: Offset(MediaQuery.of(context).size.width - 56, MediaQuery.of(context).size.height - 128),
            icon: muted ? Icons.volume_off : Icons.volume_up,
            tooltip: '音量',
            onTap: onMute,
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
  Offset _position = const Offset(10, 500); // 初始默认位置
  bool _isDragging = false;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    // 默认在左下角，与静音按钮平齐：left: 10, bottom: 80
    // bottom: 80 对应 top = height - 80 - 48（按钮高度）
    final defaultY = MediaQuery.of(context).size.height - 128.0;
    final x = prefs.getDouble('fastforward_x') ?? 10.0;
    final y = prefs.getDouble('fastforward_y') ?? defaultY;
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

/// 通用可拖动按钮组件
class _DraggableButton extends StatefulWidget {
  const _DraggableButton({
    required this.storageKey,
    required this.defaultPosition,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final String storageKey;
  final Offset defaultPosition;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_DraggableButton> createState() => _DraggableButtonState();
}

class _DraggableButtonState extends State<_DraggableButton> {
  late Offset _position;
  bool _isDragging = false;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _position = widget.defaultPosition;
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('${widget.storageKey}_x');
    final y = prefs.getDouble('${widget.storageKey}_y');
    if (x != null && y != null && mounted) {
      setState(() {
        _position = Offset(x, y);
      });
    }
  }

  Future<void> _savePosition(Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${widget.storageKey}_x', pos.dx);
    await prefs.setDouble('${widget.storageKey}_y', pos.dy);
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
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isDragging ? null : widget.onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  widget.icon,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
