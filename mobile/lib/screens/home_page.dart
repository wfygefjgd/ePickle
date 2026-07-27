import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/layout_settings.dart';
import '../services/source_catalog.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/site_logo.dart';
import 'search_screen.dart';
import 'site_feed_page.dart';

/// Primary home: site list + bottom search (always multi-site).
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

  void _onHomeSearch() {
    final q = _searchCtrl.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          initialQuery: q.isEmpty ? null : q,
        ),
      ),
    );
  }

  void _openSettings() {
    showPlayerSettingsSheet(context);
  }

  Future<void> _removeSite(SiteDef site) async {
    final lay = context.read<LayoutSettings>();
    if (site.custom) {
      await lay.removeCustomUrl(site.primaryHost);
    } else {
      await lay.toggleVideoSite(site.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutSettings>();
    final sites = layout.enabledVideoSites;
    final lives = SourceCatalog.liveSites
        .where((s) => s.ready)
        .toList(growable: false);
    final live = layout.liveSite ?? SourceCatalog.chaturbate;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('ePickle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _HomeBody(
        sites: sites,
        lives: lives,
        live: live,
        searchCtrl: _searchCtrl,
        onOpenSite: _openSite,
        onRemoveSite: _removeSite,
        onSearch: _onHomeSearch,
      ),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({
    required this.sites,
    required this.lives,
    required this.live,
    required this.searchCtrl,
    required this.onOpenSite,
    required this.onRemoveSite,
    required this.onSearch,
  });

  final List<SiteDef> sites;
  final List<SiteDef> lives;
  final SiteDef live;
  final TextEditingController searchCtrl;
  final void Function(SiteDef) onOpenSite;
  final Future<void> Function(SiteDef) onRemoveSite;
  final VoidCallback onSearch;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(
          bottom: 80,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              for (final s in widget.sites)
                _SwipeSiteTile(
                  site: s,
                  onTap: () => widget.onOpenSite(s),
                  onDelete: () => widget.onRemoveSite(s),
                  subtitle: s.custom
                      ? '用户添加'
                      : (s.mirrors.length > 1
                          ? '${s.mirrors.length} 个域名'
                          : null),
                ),
              if (widget.lives.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    '直播',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                for (final s in widget.lives)
                  _SwipeSiteTile(
                    site: s,
                    swipeEnabled: false,
                    onTap: () => widget.onOpenSite(s),
                    onDelete: () {},
                    subtitle: s.id == widget.live.id ? '默认直播' : null,
                  ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Transform.translate(
            offset: Offset(0, -bottomInset),
            child: Material(
              color: const Color(0xFF1E1E1E),
              elevation: 8,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.searchCtrl,
                          focusNode: _focusNode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => widget.onSearch(),
                          decoration: InputDecoration(
                            hintText: '搜索全部已启用网站',
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
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white38,
                              size: 20,
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
                        onPressed: widget.onSearch,
                        child: const Text('搜'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SwipeSiteTile extends StatelessWidget {
  const _SwipeSiteTile({
    required this.site,
    required this.onTap,
    required this.onDelete,
    this.subtitle,
    this.swipeEnabled = true,
  });

  final SiteDef site;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String? subtitle;
  final bool swipeEnabled;

  @override
  Widget build(BuildContext context) {
    final tile = Card(
      color: const Color(0xFF2A2A2A),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: SiteLogo(site: site, size: 44),
        title: Text(site.name, style: const TextStyle(color: Colors.white)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
    if (!swipeEnabled) return tile;
    return Dismissible(
      key: ValueKey('site_${site.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFB71C1C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: Text(
                  '移除 ${site.name}？',
                  style: const TextStyle(color: Colors.white),
                ),
                content: const Text(
                  '可从设置里一键恢复频道列表。',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      '移除',
                      style: TextStyle(color: Color(0xFFFF6B35)),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }
}
