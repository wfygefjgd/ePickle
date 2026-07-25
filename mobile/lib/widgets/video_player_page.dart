import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
          Positioned(
            top: 8,
            left: 8,
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
          Positioned(
            top: 8,
            right: 8,
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
          if (controller != null || pageLoading)
            Positioned(
              left: 10,
              bottom: 56,
              child: SafeArea(
                child: FeedSideControls(
                  muted: muted,
                  onMute: onMute,
                  onFastForward: onFastForward,
                ),
              ),
            ),
        ] else if (controller != null || pageLoading) ...[
          _buildTopBar(),
          Positioned(
            left: 10,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: FeedCircleButton(
                  icon: Icons.fullscreen,
                  onTap: onFullscreen,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 6,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
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
          ),
          Positioned(
            left: 10,
            bottom: 56,
            child: SafeArea(
              child: FeedSideControls(
                muted: muted,
                onMute: onMute,
                onFastForward: onFastForward,
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
