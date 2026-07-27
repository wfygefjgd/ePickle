import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';
import '../services/cache_manager.dart';
import '../services/layout_settings.dart';
import '../services/watch_history.dart';
import '../utils/privacy_wipe.dart';

/// Settings: quality + restore channels (no proxy / global-search toggles).
Future<void> showPlayerSettingsSheet(
  BuildContext context, {
  VoidCallback? onQualityChanged,
  List<int>? qualityHeights,
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Consumer2<AppSettings, LayoutSettings>(
            builder: (_, settings, layout, __) {
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
                    ListTile(
                      title: const Text(
                        '设置',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      dense: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: '返回',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text(
                        '跳过片头',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        '跳过片头广告；短视频自动关闭。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.skipIntro,
                      onChanged: settings.setSkipIntro,
                    ),
                    SwitchListTile(
                      title: const Text(
                        '自动横屏',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        '接近完全横置才进、明显竖回才出。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.autoRotate,
                      onChanged: settings.setAutoRotate,
                    ),
                    SwitchListTile(
                      title: const Text(
                        '卡顿自动降画质',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        '播放卡顿时自动切更低清晰度（仅本条）。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.autoLowerOnStall,
                      onChanged: settings.setAutoLowerOnStall,
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      title: const Text(
                        '一键恢复频道',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        '恢复默认网站列表与直播入口（不改画质）。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: const Icon(
                        Icons.restart_alt,
                        color: Color(0xFFFF6B35),
                      ),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                              context: ctx,
                              builder: (d) => AlertDialog(
                                backgroundColor: const Color(0xFF2A2A2A),
                                title: const Text(
                                  '恢复默认频道？',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: const Text(
                                  '将重置主页网站列表与默认直播源。',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, true),
                                    child: const Text(
                                      '恢复',
                                      style: TextStyle(color: Color(0xFFFF6B35)),
                                    ),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!ok) return;
                        await layout.restoreDefaultLayout();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已恢复默认频道'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      title: const Text(
                        '清除痕迹并退出',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        '清理 WebView 缓存、Cookie、应用数据后退出。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: const Icon(
                        Icons.cleaning_services,
                        color: Color(0xFFFF6B35),
                      ),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                              context: ctx,
                              builder: (d) => AlertDialog(
                                backgroundColor: const Color(0xFF2A2A2A),
                                title: const Text(
                                  '清除痕迹？',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: const Text(
                                  '将清理所有 WebView 缓存、Cookie、观看历史和应用数据后退出。',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, true),
                                    child: const Text(
                                      '清理并退出',
                                      style: TextStyle(color: Color(0xFFFF6B35)),
                                    ),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!ok) return;
                        if (!ctx.mounted) return;
                        await ctx.read<WatchHistory>().clear();
                        await CacheManager.clearAllCache();
                        if (ctx.mounted) Navigator.pop(ctx);
                        await PrivacyWipe.nuclearWipe();
                        await PrivacyWipe.exitApp();
                      },
                    ),
                    const Divider(color: Colors.white12),
                    const ListTile(
                      title: Text(
                        '画质',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      dense: true,
                    ),
                    for (final h in options)
                      ListTile(
                        title: Text(
                          h == 0 ? '自动（偏好 ≤720p）' : '${h}p',
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: settings.qualityCap == h
                            ? const Icon(
                                Icons.check,
                                color: Color(0xFFFF6B35),
                              )
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
      );
    },
  );
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
