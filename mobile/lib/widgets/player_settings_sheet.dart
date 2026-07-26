import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';
import '../services/layout_settings.dart';
import '../services/source_catalog.dart';

/// Shared settings sheet: skip intro, proxy, quality (manual only).
Future<void> showPlayerSettingsSheet(
  BuildContext context, {
  VoidCallback? onQualityChanged,
  VoidCallback? onProxyChanged,
  List<int>? qualityHeights,
  bool layoutExtras = false,
  Future<void> Function()? onRestoreLayout,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom: 16 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Consumer<AppSettings>(
                builder: (_, settings, __) {
                  final heights = <int>{
                    0,
                    ...(qualityHeights ?? const [360, 480, 720, 1080]),
                  };
                  final options = heights.toList()..sort();
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const ListTile(
                          title: Text('设置',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          dense: true,
                        ),
                        SwitchListTile(
                          title: const Text('跳过片头',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                            '跳过片头广告；短视频自动关闭。',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          activeThumbColor: const Color(0xFFFF6B35),
                          value: settings.skipIntro,
                          onChanged: settings.setSkipIntro,
                        ),
                        SwitchListTile(
                          title: const Text('自动横屏',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                            '接近完全横置才进、明显竖回才出；抖一下不会转。系统竖屏锁下也会转画面。',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          activeThumbColor: const Color(0xFFFF6B35),
                          value: settings.autoRotate,
                          onChanged: settings.setAutoRotate,
                        ),
                        SwitchListTile(
                          title: const Text('卡顿自动降画质',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                            '播放卡顿时自动切更低清晰度（仅本条）。从后台返回会短暂忽略，避免误判。',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          activeThumbColor: const Color(0xFFFF6B35),
                          value: settings.autoLowerOnStall,
                          onChanged: settings.setAutoLowerOnStall,
                        ),
                        if (layoutExtras) ...[
                          const Divider(color: Colors.white12),
                          const ListTile(
                            title: Text('源与布局',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            dense: true,
                          ),
                          Consumer<LayoutSettings>(
                            builder: (_, layout, __) {
                              return Column(
                                children: [
                                  SwitchListTile(
                                    title: const Text('全局搜索',
                                        style: TextStyle(color: Colors.white)),
                                    subtitle: const Text(
                                      '开启后主页搜索默认搜全部已启用网站；关闭时可弹窗确认。',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 12),
                                    ),
                                    activeThumbColor: const Color(0xFFFF6B35),
                                    value: layout.globalSearch,
                                    onChanged: layout.setGlobalSearch,
                                  ),
                                  ListTile(
                                    title: const Text('默认直播源',
                                        style: TextStyle(color: Colors.white)),
                                    subtitle: Text(
                                      layout.liveSite?.name ?? '未选',
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 12),
                                    ),
                                    trailing: DropdownButton<String>(
                                      value: layout.liveId,
                                      dropdownColor: const Color(0xFF2A2A2A),
                                      underline: const SizedBox.shrink(),
                                      items: [
                                        for (final s in SourceCatalog.liveSites)
                                          DropdownMenuItem(
                                            value: s.id,
                                            child: Text(
                                              s.name,
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) layout.setLiveId(v);
                                      },
                                    ),
                                  ),
                                  ListTile(
                                    title: const Text('恢复默认源与主页布局',
                                        style: TextStyle(color: Colors.white)),
                                    subtitle: const Text(
                                      '仅恢复网站列表、直播默认、全局搜索开关；不改代理与画质。',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 12),
                                    ),
                                    trailing: const Icon(Icons.restore,
                                        color: Color(0xFFFF6B35)),
                                    onTap: () async {
                                      await (onRestoreLayout?.call() ??
                                          layout.restoreDefaultLayout());
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                        const Divider(color: Colors.white12),
                        // C: 代理状态一眼懂
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                settings.networkStatusTitle,
                                style: const TextStyle(
                                  color: Color(0xFFFF6B35),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                settings.networkStatusDetail,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const ListTile(
                          title: Text('网络代理',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          subtitle: Text(
                            '默认跟随系统代理（不写死地址）。读不到则直连。'
                            '已开 TUN 可关掉此项。列表通但播不动时，可开 TUN 或换 HTTP 代理。',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          dense: true,
                        ),
                        SwitchListTile(
                          title: const Text('使用系统/本地代理',
                              style: TextStyle(color: Colors.white)),
                          subtitle: Text(
                            settings.proxySummary,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                          activeThumbColor: const Color(0xFFFF6B35),
                          value: settings.proxyEnabled,
                          onChanged: (v) async {
                            await settings.setProxyEnabled(v);
                            onProxyChanged?.call();
                          },
                        ),
                        if (settings.proxyEnabled)
                          _ProxyEditor(
                            settings: settings,
                            onApplied: onProxyChanged,
                          ),
                        const Divider(color: Colors.white12),
                        const ListTile(
                          title: Text('画质',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          dense: true,
                        ),
                        for (final h in options)
                          ListTile(
                            title: Text(
                              h == 0 ? '自动（偏好 ≤720p）' : '${h}p',
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: settings.qualityCap == h
                                ? const Icon(Icons.check,
                                    color: Color(0xFFFF6B35))
                                : null,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await settings.setQualityCap(h);
                              onQualityChanged?.call();
                            },
                          ),
                        const SizedBox(height: 16),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: _AppVersionLabel(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Floating close button at top-left
            Positioned(
              left: 16,
              top: 56,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ProxyEditor extends StatefulWidget {
  const _ProxyEditor({required this.settings, this.onApplied});

  final AppSettings settings;
  final VoidCallback? onApplied;

  @override
  State<_ProxyEditor> createState() => _ProxyEditorState();
}

class _ProxyEditorState extends State<_ProxyEditor> {
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _host = TextEditingController(text: s.proxyHost);
    _port = TextEditingController(
      text: s.proxyPort > 0 ? '${s.proxyPort}' : '',
    );
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await widget.settings.setProxyHost(_host.text);
    final p = int.tryParse(_port.text.trim());
    await widget.settings.setProxyPort(p ?? 0);
    widget.onApplied?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.settings.proxySummary),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _redetect() async {
    await widget.settings.refreshSystemProxy();
    if (!mounted) return;

    _host.text = widget.settings.proxyHost;
    _port.text =
        widget.settings.proxyPort > 0 ? '${widget.settings.proxyPort}' : '';
    widget.onApplied?.call();

    setState(() {});

    // Use Dialog to show feedback in current settings page
    if (mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            '代理检测结果',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            widget.settings.proxySummary,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定', style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('HTTP'),
                selected: s.proxyType == 'http',
                onSelected: (_) async {
                  await s.setProxyType('http');
                  widget.onApplied?.call();
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('SOCKS5'),
                selected: s.proxyType == 'socks5',
                onSelected: (_) async {
                  await s.setProxyType('socks5');
                  widget.onApplied?.call();
                  setState(() {});
                },
              ),
              const Spacer(),
              TextButton(
                onPressed: _redetect,
                child: const Text('重新检测系统代理'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _host,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '主机（可空=未配置）',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '由系统检测或手动填写',
              hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _port,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '端口（可空）',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '不写死默认端口',
              hintStyle: TextStyle(color: Colors.white30),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
            ),
            child: const Text('保存手动代理'),
          ),
        ],
      ),
    );
  }
}

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  String _label = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _label = 'v${info.version}');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_label.isEmpty) return const SizedBox.shrink();
    return Text(
      _label,
      style: const TextStyle(color: Colors.white24, fontSize: 11),
    );
  }
}
