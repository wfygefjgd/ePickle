import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
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
    final showAllButtons = context.watch<AppSettings>().showImmersiveButtons;

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
          // 全屏模式：根据设置显示按钮
          if (showAllButtons) ...[
            // 固定位置的设置按钮
            Positioned(
              left: 8,
              top: 8,
              child: SafeArea(
                child: _LongPressDraggableButton(
                  storageKey: 'settings_button_immersive',
                  defaultOffset: const Offset(8, 8),
                  icon: Icons.tune,
                  onTap: onOpenSettings,
                ),
              ),
            ),
            // 固定位置的全屏按钮
            Positioned(
              right: 8,
              top: 8,
              child: SafeArea(
                child: _LongPressDraggableButton(
                  storageKey: 'fullscreen_button_immersive',
                  defaultOffset: const Offset(8, 8),
                  icon: Icons.fullscreen_exit,
                  onTap: onFullscreen,
                ),
              ),
            ),
            // 固定位置的音量按钮（右边）
            Positioned(
              right: 8,
              bottom: 80,
              child: SafeArea(
                child: _LongPressDraggableButton(
                  storageKey: 'mute_button_immersive',
                  defaultOffset: const Offset(8, 80),
                  icon: muted ? Icons.volume_off : Icons.volume_up,
                  onTap: onMute,
                ),
              ),
            ),
          ] else ...[
            // 只显示快进按钮和退出全屏按钮（右上角）
            Positioned(
              right: 8,
              top: 8,
              child: SafeArea(
                child: _LongPressDraggableButton(
                  storageKey: 'fullscreen_button_immersive',
                  defaultOffset: const Offset(8, 8),
                  icon: Icons.fullscreen_exit,
                  onTap: onFullscreen,
                ),
              ),
            ),
          ],
          // 快进按钮始终显示（左边）
          Positioned(
            left: 8,
            bottom: 80,
            child: SafeArea(
              child: _LongPressDraggableButton(
                storageKey: 'fastforward_button_immersive',
                defaultOffset: const Offset(8, 80),
                icon: Icons.forward_30,
                onTap: onFastForward,
              ),
            ),
          ),
        ] else ...[
          _buildTopBar(),
          // 固定位置的全屏按钮（左上角）
          Positioned(
            left: 10,
            top: 8,
            child: SafeArea(
              child: _LongPressDraggableButton(
                storageKey: 'fullscreen_button_normal',
                defaultOffset: const Offset(10, 8),
                icon: Icons.fullscreen,
                onTap: onFullscreen,
              ),
            ),
          ),
          // 固定位置的设置按钮（右上角，与全屏按钮平齐）
          Positioned(
            right: 10,
            top: 8,
            child: SafeArea(
              child: _LongPressDraggableButton(
                storageKey: 'settings_button_normal',
                defaultOffset: const Offset(10, 8),
                icon: Icons.tune,
                onTap: onOpenSettings,
              ),
            ),
          ),
          // 固定位置的快进按钮（左边）
          Positioned(
            left: 10,
            bottom: 80,
            child: SafeArea(
              child: _LongPressDraggableButton(
                storageKey: 'fastforward_button_normal',
                defaultOffset: const Offset(10, 80),
                icon: Icons.forward_30,
                onTap: onFastForward,
              ),
            ),
          ),
          // 固定位置的音量按钮（右边，与快进平齐）
          Positioned(
            right: 10,
            bottom: 80,
            child: SafeArea(
              child: _LongPressDraggableButton(
                storageKey: 'mute_button_normal',
                defaultOffset: const Offset(10, 80),
                icon: muted ? Icons.volume_off : Icons.volume_up,
                onTap: onMute,
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

/// 支持长按拖动的按钮组件（默认固定）
class _LongPressDraggableButton extends StatefulWidget {
  const _LongPressDraggableButton({
    required this.storageKey,
    required this.defaultOffset,
    required this.icon,
    required this.onTap,
  });

  final String storageKey;
  final Offset defaultOffset; // 相对于 Positioned 的偏移
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_LongPressDraggableButton> createState() =>
      _LongPressDraggableButtonState();
}

class _LongPressDraggableButtonState
    extends State<_LongPressDraggableButton> {
  Offset? _savedOffset; // 保存的偏移量（相对于默认位置）
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
            // 限制拖动范围：确保按钮不会超出屏幕边界
            final size = MediaQuery.of(context).size;
            final padding = MediaQuery.of(context).padding;
            _currentDragOffset = Offset(
              _currentDragOffset.dx.clamp(
                -widget.defaultOffset.dx,
                size.width - widget.defaultOffset.dx - 48 - padding.right,
              ),
              _currentDragOffset.dy.clamp(
                -widget.defaultOffset.dy,
                size.height - widget.defaultOffset.dy - 48 - padding.bottom,
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
          scale: _isDragging ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: _isDragging ? Colors.black87 : Colors.black54,
              shape: const CircleBorder(),
              child: Center(
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
