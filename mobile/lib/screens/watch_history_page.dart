import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/source_catalog.dart';
import '../services/watch_history.dart';
import '../widgets/video_card.dart';
import 'search_feed_screen.dart';

class WatchHistoryPage extends StatelessWidget {
  const WatchHistoryPage({super.key});

  SearchSource _sourceFor(VideoItem item) {
    final u = item.url.toLowerCase();
    if (u.contains('xvideos') || u.contains('xhamster')) {
      return SearchSource.x;
    }
    if (u.contains('mitao') ||
        u.contains('91porn') ||
        RegExp(r'/vod/play/id/').hasMatch(u)) {
      return SearchSource.zhong;
    }
    if (u.contains('pornhub')) return SearchSource.ph;
    return SearchSource.generic;
  }

  SiteDef? _siteFor(VideoItem item, SearchSource source) {
    if (source != SearchSource.generic) return null;
    try {
      final host = Uri.parse(item.url).host.toLowerCase();
      if (host.isEmpty) return null;
      for (final s in SourceCatalog.all) {
        for (final m in s.mirrors) {
          final h = Uri.tryParse(m)?.host.toLowerCase() ?? '';
          if (h.isNotEmpty && (host == h || host.endsWith('.$h'))) {
            return s;
          }
        }
        final ph =
            s.primaryHost.toLowerCase().replaceAll(RegExp(r'^https?://'), '');
        final phHost = ph.split('/').first;
        if (host == phHost || host.endsWith('.$phHost')) return s;
      }
    } catch (_) {}
    return null;
  }

  void _open(BuildContext context, List<VideoItem> items, int index) {
    final item = items[index];
    final source = _sourceFor(item);
    final site = _siteFor(item, source);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchFeedScreen(
          items: List<VideoItem>.from(items),
          source: source,
          initialIndex: index,
          title: '历史',
          site: site,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<WatchHistory>();
    final items = history.items;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text('清空历史？',
                        style: TextStyle(color: Colors.white)),
                    content: const Text(
                      '将删除全部本地观看记录。',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空',
                            style: TextStyle(color: Color(0xFFFF6B35))),
                      ),
                    ],
                  ),
                );
                if (ok == true) await history.clear();
              },
              child: const Text('清空', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: !history.ready
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            )
          : items.isEmpty
              ? const Center(
                  child: Text(
                    '暂无观看记录',
                    style: TextStyle(color: Colors.white38, fontSize: 15),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return Dismissible(
                      key: ValueKey('${item.viewkey}_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFB71C1C),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      onDismissed: (_) => history.remove(item),
                      child: VideoCard(
                        item: item,
                        onTap: () => _open(context, items, i),
                      ),
                    );
                  },
                ),
    );
  }
}
