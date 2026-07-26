import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/generic_site_api.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/source_catalog.dart';
import '../services/xvideos_api.dart';
import '../utils/playback_helpers.dart';
import '../widgets/site_logo.dart';
import '../widgets/video_card.dart';
import 'search_feed_screen.dart';

/// Search within a single site only.
class SiteSearchPage extends StatefulWidget {
  const SiteSearchPage({super.key, required this.site});

  final SiteDef site;

  @override
  State<SiteSearchPage> createState() => _SiteSearchPageState();
}

class _SiteSearchPageState extends State<SiteSearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<VideoItem> _items = [];
  bool _loading = false;
  String? _error;
  int _gen = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      List<VideoItem> list;
      final site = widget.site;
      if (site.id == 'pornhub') {
        list = await context.read<PhubApi>().search(q);
      } else if (site.id == 'xvideos') {
        list = await context.read<XvideosApi>().search(q);
      } else if (site.id == 'mitao') {
        list = await context.read<MitaoApi>().search(q);
      } else {
        list = await context.read<GenericSiteApi>().search(site, q);
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = list;
        _loading = false;
        if (list.isEmpty) _error = '无结果';
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = PlaybackHelpers.friendlyError(e);
      });
    }
  }

  SearchSource get _feedSource {
    switch (widget.site.id) {
      case 'xvideos':
        return SearchSource.x;
      case 'mitao':
        return SearchSource.zhong;
      case 'pornhub':
        return SearchSource.ph;
      default:
        return SearchSource.generic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Row(
          children: [
            SiteLogo(site: site, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '搜索 · ${site.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _run(),
                    decoration: InputDecoration(
                      hintText: '仅搜索 ${site.name}',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                  ),
                  onPressed: _loading ? null : _run,
                  child: const Text('搜'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                  )
                : _error != null && _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(
                            child: Text(
                              '输入关键词搜索本站',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              return VideoCard(
                                item: _items[i],
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SearchFeedScreen(
                                        items: List<VideoItem>.from(_items),
                                        source: _feedSource,
                                        initialIndex: i,
                                        title: site.name,
                                        site: site,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
