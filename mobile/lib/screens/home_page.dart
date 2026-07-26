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

  static const _previewCount = 8;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutSettings>();
    final sites = layout.enabledVideoSites;
    final ready = sites.where((s) => s.ready).toList();
    final soon = sites.where((s) => !s.ready).toList();
    final lives = SourceCatalog.liveSites;
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    '可用 (${ready.length})',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                for (final s in ready)
                  _SiteTile(
                    site: s,
                    onTap: () => _openSite(s),
                    mirrorHint: s.mirrors.length > 1
                        ? '${s.mirrors.length} 个域名'
                        : null,
                  ),
                if (soon.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ExpandableSiteSection(
                    title: '更多网站 · 即将支持 (${soon.length})',
                    initiallyExpanded: soon.length <= _previewCount,
                    children: [
                      for (final s in soon)
                        _SiteTile(
                          site: s,
                          onTap: () => _openSite(s),
                          mirrorHint: s.mirrors.isNotEmpty
                              ? '${s.mirrors.length} 个域名'
                              : null,
                        ),
                    ],
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.add_circle_outline,
                      color: Color(0xFFFF6B35)),
                  title: const Text(
                    '管理网站列表',
                    style: TextStyle(color: Color(0xFFFF6B35)),
                  ),
                  subtitle: const Text(
                    '勾选显示 / 取消隐藏',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onTap: _showAddSites,
                ),
                const Divider(color: Colors.white12, height: 28),
                _ExpandableSiteSection(
                  title: '直播 (${lives.length})',
                  initiallyExpanded: true,
                  children: [
                    for (final s in lives)
                      _SiteTile(
                        site: s,
                        subtitle: s.id == live.id
                            ? (s.ready ? '默认直播' : '默认入口 · 适配开发中')
                            : (s.ready ? '点击进入' : '即将支持'),
                        mirrorHint: s.mirrors.isNotEmpty
                            ? '${s.mirrors.length} 个域名'
                            : null,
                        onTap: () {
                          if (s.id == live.id) {
                            _openLive();
                          } else {
                            _openSite(s);
                          }
                        },
                      ),
                  ],
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

class _ExpandableSiteSection extends StatefulWidget {
  const _ExpandableSiteSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_ExpandableSiteSection> createState() => _ExpandableSiteSectionState();
}

class _ExpandableSiteSectionState extends State<_ExpandableSiteSection> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          ...widget.children,
        ],
        const SizedBox(height: 8),
      ],
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
    this.mirrorHint,
  });

  final SiteDef site;
  final VoidCallback onTap;
  final String? subtitle;
  final String? mirrorHint;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle ??
        (site.ready
            ? (mirrorHint != null ? '点击进入 · $mirrorHint' : '点击进入')
            : (mirrorHint != null ? '即将支持 · $mirrorHint' : '即将支持'));
    return Card(
      color: const Color(0xFF2A2A2A),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _SiteAvatar(site: site),
        title: Text(site.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          sub,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
