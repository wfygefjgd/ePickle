import 'package:flutter/material.dart';

import '../services/source_catalog.dart';
import 'video_feed_screen.dart';

/// Secondary page: one site + top tag chips + vertical feed.
class SiteFeedPage extends StatefulWidget {
  const SiteFeedPage({super.key, required this.site});

  final SiteDef site;

  @override
  State<SiteFeedPage> createState() => _SiteFeedPageState();
}

class _SiteFeedPageState extends State<SiteFeedPage> {
  late int _tagIndex;

  @override
  void initState() {
    super.initState();
    _tagIndex = 0;
  }

  VideoFeedKind get _feedKind {
    final tags = widget.site.tags;
    if (tags.isEmpty) return VideoFeedKind.hot;
    final t = tags[_tagIndex.clamp(0, tags.length - 1)];
    return t.feedKind ?? VideoFeedKind.hot;
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final tags = site.tags;
    final chips = tags.length > 4 ? tags.take(4).toList() : tags;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Color(site.color),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        site.letter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        site.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!site.ready)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Text(
                          '即将支持',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = i == _tagIndex;
                      final label = i == 0 ? '热门' : chips[i].label;
                      return ChoiceChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: site.ready
                            ? (_) {
                                if (i == _tagIndex) return;
                                setState(() => _tagIndex = i);
                              }
                            : null,
                        selectedColor: const Color(0xFFFF6B35),
                        backgroundColor: const Color(0xFF2A2A2A),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 13,
                        ),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Expanded(
            child: site.ready
                ? VideoFeedScreen(
                    key: ValueKey('${site.id}_$_tagIndex'),
                    kind: _feedKind,
                    autoStart: true,
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '该站点适配开发中，请先使用 Pornhub / XVideos / 中文字幕。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, height: 1.4),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
