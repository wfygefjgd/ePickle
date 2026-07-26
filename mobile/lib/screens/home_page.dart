import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/layout_settings.dart';
import '../services/source_catalog.dart';
import '../widgets/player_settings_sheet.dart';
import 'search_screen.dart';
import 'site_feed_page.dart';

/// Primary home: site list + bottom search (home only).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openSite(SiteDef site) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SiteFeedPage(site: site)),
    );
  }

  void _openLive() {
    final layout = context.read<LayoutSettings>();
    final live = layout.liveSite ?? SourceCatalog.stripchat;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SiteFeedPage(site: live)),
    );
  }

  Future<void> _onHomeSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      );
      return;
    }
    final layout = context.read<LayoutSettings>();
    var global = layout.globalSearch;
    if (!global) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('搜索范围', style: TextStyle(color: Colors.white)),
          content: const Text(
            '默认搜索全部已启用网站。\n可在设置底部开启「全局搜索」作为默认。',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('搜索全部'),
            ),
          ],
        ),
      );
      if (choice != true || !mounted) return;
      global = true;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: q, forceGlobal: global),
      ),
    );
  }

  Future<void> _showAddSites() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Consumer<LayoutSettings>(
            builder: (_, lay, __) {
              final enabled = lay.enabledVideoIds.toSet();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '添加网站',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '勾选后显示在主页列表。灰色为即将支持。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final s in SourceCatalog.videoSites)
                            SwitchListTile(
                              value: enabled.contains(s.id),
                              activeThumbColor: const Color(0xFFFF6B35),
                              title: Text(
                                s.name,
                                style: TextStyle(
                                  color: s.ready ? Colors.white : Colors.white38,
                                ),
                              ),
                              subtitle: Text(
                                s.ready ? '可用' : '即将支持',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              secondary: _SiteAvatar(site: s, size: 36),
                              onChanged: (v) => lay.toggleVideoSite(s.id, v),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  void _openSettings() {
    final layout = context.read<LayoutSettings>();
    showPlayerSettingsSheet(
      context,
      layoutExtras: true,
      onRestoreLayout: () async {
        await layout.restoreDefaultLayout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已恢复默认源与主页布局'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutSettings>();
    final sites = layout.enabledVideoSites;
    final live = layout.liveSite ?? SourceCatalog.stripchat;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('PHUB Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    '网站',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                for (final s in sites)
                  _SiteTile(
                    site: s,
                    onTap: () => _openSite(s),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline,
                      color: Color(0xFFFF6B35)),
                  title: const Text(
                    '添加网站',
                    style: TextStyle(color: Color(0xFFFF6B35)),
                  ),
                  onTap: _showAddSites,
                ),
                const Divider(color: Colors.white12, height: 28),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    '直播 · 搜索',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                _SiteTile(
                  site: live,
                  subtitle: live.ready ? null : '默认入口 · 适配开发中',
                  onTap: _openLive,
                ),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white70),
                  title: const Text('搜索', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    '打开完整搜索页',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          // Home-only bottom search bar
          Material(
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
                        controller: _searchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _onHomeSearch(),
                        decoration: InputDecoration(
                          hintText: layout.globalSearch
                              ? '搜索全部已启用网站'
                              : '搜索（可搜全部网站）',
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
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.white38, size: 20),
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
                      onPressed: _onHomeSearch,
                      child: const Text('搜'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiteAvatar extends StatelessWidget {
  const _SiteAvatar({required this.site, this.size = 44});

  final SiteDef site;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(site.color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        site.letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.onTap,
    this.subtitle,
  });

  final SiteDef site;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2A2A2A),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _SiteAvatar(site: site),
        title: Text(site.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          subtitle ?? (site.ready ? '点击进入' : '即将支持'),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
