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
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
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
      _page = 0;
      _hasMore = false;
    });
    try {
      final list = await _searchPage(q, 1);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = list;
        _loading = false;
        _page = 1;
        _hasMore = list.isNotEmpty;
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

  Future<List<VideoItem>> _searchPage(String query, int page) {
    final site = widget.site;
    if (site.id == 'pornhub') {
      return context.read<PhubApi>().search(query, page: page);
    }
    if (site.id == 'xvideos') {
      return context.read<XvideosApi>().search(query, page: page);
    }
    if (site.id == 'mitao') {
      return context.read<MitaoApi>().search(query, page: page);
    }
    return context.read<GenericSiteApi>().search(site, query, page: page);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    final gen = _gen;
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final list = await _searchPage(q, nextPage);
      if (!mounted || gen != _gen) return;
      final seen = _items.map((e) => e.viewkey).toSet();
      final additions = list.where((e) => seen.add(e.viewkey)).toList();
      setState(() {
        _items.addAll(additions);
        _page = nextPage;
        _hasMore = list.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingMore = false;
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
      // Parent [SiteFeedPage] already draws a floating back; hide AppBar leading.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            SiteLogo(site: site, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text('搜索 · ${site.name}', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: _SiteSearchBody(
        site: site,
        items: _items,
        loading: _loading,
        loadingMore: _loadingMore,
        hasMore: _hasMore,
        error: _error,
        ctrl: _ctrl,
        focus: _focus,
        feedSource: _feedSource,
        onRun: _run,
        onLoadMore: _loadMore,
      ),
    );
  }
}

class _SiteSearchBody extends StatelessWidget {
  const _SiteSearchBody({
    required this.site,
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.ctrl,
    required this.focus,
    required this.feedSource,
    required this.onRun,
    required this.onLoadMore,
  });

  final SiteDef site;
  final List<VideoItem> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final TextEditingController ctrl;
  final FocusNode focus;
  final SearchSource feedSource;
  final VoidCallback onRun;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          bottom: 80,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                )
              : error != null && items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B35),
                              ),
                              onPressed: loading ? null : onRun,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : items.isEmpty
                      ? const Center(
                          child: Text(
                            '输入关键词搜索本站',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length + (hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == items.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: loadingMore
                                      ? const CircularProgressIndicator(
                                          color: Color(0xFFFF6B35),
                                        )
                                      : TextButton.icon(
                                          onPressed: onLoadMore,
                                          icon: const Icon(Icons.expand_more),
                                          label: const Text('加载更多'),
                                        ),
                                ),
                              );
                            }
                            return VideoCard(
                              item: items[i],
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SearchFeedScreen(
                                      items: List<VideoItem>.from(items),
                                      source: feedSource,
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
        // bottom:0 is already above keyboard when resizeToAvoidBottomInset:true
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: const Color(0xFF1E1E1E),
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        focusNode: focus,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => onRun(),
                        decoration: InputDecoration(
                          hintText: '仅搜索 ${site.name}',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          isDense: true,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: loading ? null : onRun,
                      child: const Text('搜'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

