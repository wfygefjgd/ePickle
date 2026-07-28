import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/generic_site_api.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/source_catalog.dart';
import '../services/translator.dart';
import '../services/xvideos_api.dart';
import '../utils/playback_helpers.dart';
import '../widgets/site_logo.dart';
import '../widgets/video_card.dart';
import 'search_feed_screen.dart';

/// Shared category directory for both VOD and live sites.
class SiteTagDirectoryPage extends StatefulWidget {
  const SiteTagDirectoryPage({super.key, required this.site});
  final SiteDef site;

  @override
  State<SiteTagDirectoryPage> createState() => _SiteTagDirectoryPageState();
}

class _SiteTagDirectoryPageState extends State<SiteTagDirectoryPage> {
  SiteTag? _selected;
  List<VideoItem> _items = const [];
  bool _loading = false;
  String? _error;

  Future<void> _load(SiteTag tag) async {
    final api = context.read<GenericSiteApi>();
    final translator = context.read<Translator>();
    setState(() {
      _selected = tag;
      _loading = true;
      _error = null;
      _items = const [];
    });
    try {
      final raw = await _fetchItems(api, tag);
      final translated = await translator.batchEnToZh(raw.map((e) => e.title).toList());
      if (!mounted) return;
      setState(() {
        _items = [
          for (var i = 0; i < raw.length; i++)
            raw[i].copyWith(title: translated[i]),
        ];
        _loading = false;
        if (_items.isEmpty) _error = '\u6682\u65e0\u6b63\u5728\u64ad\u653e\u7684\u5185\u5bb9';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = PlaybackHelpers.friendlyError(e);
      });
    }
  }

  Future<List<VideoItem>> _fetchItems(GenericSiteApi api, SiteTag tag) {
    switch (widget.site.id) {
      case 'pornhub':
        return tag.id == 'asian'
            ? context.read<PhubApi>().fetchAsian(limit: 40)
            : context.read<PhubApi>().fetchRecommend(limit: 40);
      case 'xvideos':
        return context.read<XvideosApi>().fetchFeed(limit: 40);
      case 'mitao':
        return context.read<MitaoApi>().fetchZhong(limit: 40);
      default:
        return api.fetchFeed(widget.site, tagId: tag.id, limit: 40);
    }
  }

  SearchSource get _source => SearchSource.generic;

  @override
  Widget build(BuildContext context) {
    final tags = widget.site.tags;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          SiteLogo(site: widget.site, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text('\u6807\u7b7e \u00b7 ${widget.site.name}')),
        ]),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 116,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              scrollDirection: Axis.horizontal,
              itemCount: tags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final tag = tags[i];
                final selected = tag.id == _selected?.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _load(tag),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 86,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFF6B35).withValues(alpha: .22)
                          : const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFF6B35)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(selected ? tag.iconSelected : tag.icon,
                            color: selected
                                ? const Color(0xFFFF6B35)
                                : Colors.white70,
                            size: 30),
                        const SizedBox(height: 7),
                        Text(tag.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.white60)));
    if (_selected == null) {
      return const Center(child: Text('\u8bf7\u9009\u62e9\u4e00\u4e2a\u6807\u7b7e', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _items.length,
      itemBuilder: (_, i) => VideoCard(
        item: _items[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SearchFeedScreen(
            items: List<VideoItem>.from(_items),
            source: _source,
            initialIndex: i,
            title: widget.site.name,
            site: widget.site,
          ),
        )),
      ),
    );
  }
}
