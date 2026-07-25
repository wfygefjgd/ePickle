import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_chrome.dart';
import '../widgets/player_settings_sheet.dart';
import 'search_screen.dart';
import 'video_feed_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _hotKey = GlobalKey<VideoFeedScreenState>();
  final _asianKey = GlobalKey<VideoFeedScreenState>();
  final _xKey = GlobalKey<VideoFeedScreenState>();
  final _zhongKey = GlobalKey<VideoFeedScreenState>();

  List<GlobalKey<VideoFeedScreenState>> get _feedKeys =>
      [_hotKey, _asianKey, _xKey, _zhongKey];

  void _openSettings() {
    showPlayerSettingsSheet(context);
  }

  void _onTabSelected(int i) {
    if (i == _index) return;
    // Pause/dispose players on all feed tabs (saves memory; list cache kept).
    for (final k in _feedKeys) {
      k.currentState?.pausePlayback(releasePlayers: true);
    }
    setState(() => _index = i);
    // Start the newly selected feed after frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != i) return;
      if (i >= 0 && i < _feedKeys.length) {
        _feedKeys[i].currentState?.startPlaying();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hotKey.currentState?.startPlaying();
    });
  }

  @override
  Widget build(BuildContext context) {
    final immersive =
        context.select<PlayerChrome, bool>((c) => c.immersive);

    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Keep all tabs alive — no white flash / re-fetch on tab switch.
          IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: [
              VideoFeedScreen(
                key: _hotKey,
                kind: VideoFeedKind.hot,
                autoStart: false,
              ),
              VideoFeedScreen(
                key: _asianKey,
                kind: VideoFeedKind.asian,
                autoStart: false,
              ),
              VideoFeedScreen(
                key: _xKey,
                kind: VideoFeedKind.x,
                autoStart: false,
              ),
              VideoFeedScreen(
                key: _zhongKey,
                kind: VideoFeedKind.zhong,
                autoStart: false,
              ),
              const SearchScreen(key: ValueKey('search')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: immersive
          ? null
          : RepaintBoundary(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _onTabSelected,
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: const Color(0x33FF6B35),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.local_fire_department_outlined),
                        selectedIcon: Icon(Icons.local_fire_department,
                            color: Color(0xFFFF6B35)),
                        label: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.public_outlined),
                        selectedIcon:
                            Icon(Icons.public, color: Color(0xFFFF6B35)),
                        label: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.cancel_outlined),
                        selectedIcon: Icon(Icons.cancel,
                            color: Color(0xFFFF6B35)),
                        label: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.category_outlined),
                        selectedIcon:
                            Icon(Icons.category, color: Color(0xFFFF6B35)),
                        label: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        selectedIcon:
                            Icon(Icons.search, color: Color(0xFFFF6B35)),
                        label: '',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
