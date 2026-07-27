import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/layout_settings.dart';
import '../services/source_catalog.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/site_logo.dart';
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
    final live = layout.liveSite ?? SourceCatalog.chaturbate;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SiteFeedPage(site: live)),
    );
  }

  void _onHomeSearch() {
    final q = _searchCtrl.text.trim();
    final layout = context.read<LayoutSettings>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          initialQuery: q.isEmpty ? null : q,
          forceGlobal: layout.globalSearch || q.isNotEmpty,
        ),
      ),
    );
  }

  Future<void> _showAddSites() async {
    final customCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
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
                        '管理网站',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '勾选内置站，或粘贴自定义网址添加。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: customCtrl,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'https://example.com',
                                hintStyle:
                                    const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35),
                            ),
                            onPressed: () async {
                              await lay.addCustomUrl(customCtrl.text);
                              customCtrl.clear();
                            },
                            child: const Text('添加'),
                          ),
                        ],
                      ),
                      if (lay.customUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final u in lay.customUrls)
                          ListTile(
                            dense: true,
                            title: Text(
                              u,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.white38),
                              onPressed: () => lay.removeCustomUrl(u),
                            ),
                          ),
                      ],
                      const Divider(color: Colors.white12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.42,
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
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  !s.ready
                                      ? '解析待修复 · 暂不作为可播放频道'
                                      : (s.id == 'freeporn'
                                          ? '目录站 · 解析外链 / 网页兜底'
                                          : (s.mirrors.isNotEmpty
                                              ? '${s.mirrors.length} 个域名 · 通用解析'
                                              : '通用解析')),
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                                secondary: SiteLogo(site: s, size: 36),
                                onChanged: s.ready
                                    ? (v) => lay.toggleVideoSite(s.id, v)
                                    : null,
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
          ),
        );
      },
    );
    customCtrl.dispose();
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
    final builtIn = sites.where((s) => !s.custom).toList();
    final custom = sites.where((s) => s.custom).toList();
    final lives = SourceCatalog.liveSites;
    final live = layout.liveSite ?? SourceCatalog.chaturbate;
    final head = builtIn.take(_previewCount).toList();
    final rest = builtIn.length > _previewCount
        ? builtIn.sublist(_previewCount)
        : <SiteDef>[];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('ePickle'),
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
                    '网站 (${builtIn.length})',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                for (final s in head)
                  _SiteTile(
                    site: s,
                    onTap: () => _openSite(s),
                    mirrorHint:
                        s.mirrors.length > 1 ? '${s.mirrors.length} 个域名' : null,
                  ),
                if (rest.isNotEmpty)
                  _ExpandableSiteSection(
                    title: '更多网站 (${rest.length})',
                    initiallyExpanded: false,
                    children: [
                      for (final s in rest)
                        _SiteTile(
                          site: s,
                          onTap: () => _openSite(s),
                          mirrorHint: s.mirrors.isNotEmpty
                              ? '${s.mirrors.length} 个域名'
                              : null,
                        ),
                    ],
                  ),
                if (custom.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _ExpandableSiteSection(
                    title: '自定义网址 (${custom.length})',
                    initiallyExpanded: true,
                    children: [
                      for (final s in custom)
                        _SiteTile(
                          site: s,
                          onTap: () => _openSite(s),
                          subtitle: '用户添加 · 通用解析',
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
                        onTap: s.ready
                            ? () {
                                if (s.id == live.id) {
                                  _openLive();
                                } else {
                                  _openSite(s);
                                }
                              }
                            : null,
                      ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white70),
                  title:
                      const Text('搜索', style: TextStyle(color: Colors.white)),
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
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _onHomeSearch(),
                        decoration: InputDecoration(
                          hintText:
                              layout.globalSearch ? '搜索全部已启用网站' : '搜索（可搜全部网站）',
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

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.onTap,
    this.subtitle,
    this.mirrorHint,
  });

  final SiteDef site;
  final VoidCallback? onTap;
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
        leading: SiteLogo(site: site, size: 44),
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
