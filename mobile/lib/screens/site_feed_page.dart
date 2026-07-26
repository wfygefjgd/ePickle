import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_chrome.dart';
import '../services/source_catalog.dart';
import 'site_search_page.dart';
import 'video_feed_screen.dart';

/// Secondary page: bottom tabs (site sections) + search tab + back.
class SiteFeedPage extends StatefulWidget {
  const SiteFeedPage({super.key, required this.site});

  final SiteDef site;

  @override
  State<SiteFeedPage> createState() => _SiteFeedPageState();
}

class _SiteFeedPageState extends State<SiteFeedPage> {
  int _index = 0;
  final List<GlobalKey<VideoFeedScreenState>> _keys = [];

  /// Content tabs only (no search).
  List<SiteTag> get _contentTabs {
    final t = widget.site.tags;
    if (t.isEmpty) return const [];
    return t.length > 4 ? t.sublist(0, 4) : List<SiteTag>.from(t);
  }

  /// Bottom destinations = content tabs + search.
  int get _searchIndex => _contentTabs.length;

  int get _destinationCount => _contentTabs.length + 1;

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keys.isNotEmpty) {
        _keys[0].currentState?.startPlaying();
      }
    });
  }

  void _ensureKeys() {
    final n = _contentTabs.length;
    while (_keys.length < n) {
      _keys.add(GlobalKey<VideoFeedScreenState>());
    }
    while (_keys.length > n) {
      _keys.removeLast();
    }
  }

  VideoFeedKind _kindAt(int i) {
    final tabs = _contentTabs;
    if (tabs.isEmpty) return VideoFeedKind.hot;
    return tabs[i.clamp(0, tabs.length - 1)].feedKind ?? VideoFeedKind.hot;
  }

  void _onTabSelected(int i) {
    if (i == _index) return;
    final chrome = context.read<PlayerChrome>();
    if (chrome.immersive) {
      // ignore: unawaited_futures
      chrome.exitFullscreen();
    }

    // Leaving content tab → pause players
    if (_index < _keys.length) {
      for (final k in _keys) {
        k.currentState?.pausePlayback(releasePlayers: true);
      }
    }

    setState(() => _index = i);

    // Entering content tab → start play
    if (i < _keys.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _index != i) return;
        _keys[i].currentState?.startPlaying();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    final site = widget.site;
    final tabs = _contentTabs;
    final immersive =
        context.select<PlayerChrome, bool>((c) => c.immersive);
    final onSearch = _index >= _searchIndex;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (tabs.isEmpty)
            const Center(
              child: Text('无标签', style: TextStyle(color: Colors.white54)),
            )
          else if (onSearch)
            SiteSearchPage(key: ValueKey('search_${site.id}'), site: site)
          else
            IndexedStack(
              index: _index.clamp(0, tabs.length - 1),
              sizing: StackFit.expand,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  VideoFeedScreen(
                    key: _keys[i],
                    kind: _kindAt(i),
                    site: site,
                    tagId: tabs[i].id,
                    autoStart: false,
                  ),
              ],
            ),
          if (!immersive)
            Positioned(
              left: 4,
              top: 0,
              child: SafeArea(
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '返回',
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: immersive || tabs.isEmpty
          ? null
          : RepaintBoundary(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: NavigationBar(
                    selectedIndex: _index.clamp(0, _destinationCount - 1),
                    onDestinationSelected: _onTabSelected,
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: const Color(0x33FF6B35),
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysHide,
                    destinations: [
                      for (final t in tabs)
                        NavigationDestination(
                          icon: Icon(t.icon),
                          selectedIcon: Icon(
                            t.iconSelected,
                            color: const Color(0xFFFF6B35),
                          ),
                          label: t.label,
                        ),
                      const NavigationDestination(
                        icon: Icon(Icons.search),
                        selectedIcon: Icon(
                          Icons.search,
                          color: Color(0xFFFF6B35),
                        ),
                        label: '搜',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
