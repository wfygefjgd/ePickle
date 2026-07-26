import 'package:flutter/material.dart';

import '../models/feed_kind.dart';

/// Built-in site directory. Adapters fill data later; PH / X / 中 already wired.
enum SiteKind { video, live }

class SiteTag {
  const SiteTag({
    required this.id,
    required this.label,
    this.feedKind,
    this.icon = Icons.local_fire_department_outlined,
    this.iconSelected = Icons.local_fire_department,
  });

  final String id;
  final String label;
  /// Maps to existing fetch path; null = placeholder.
  final VideoFeedKind? feedKind;
  final IconData icon;
  final IconData iconSelected;
}

class SiteDef {
  const SiteDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.tags,
    required this.color,
    required this.letter,
    this.mirrors = const [],
    this.searchable = true,
    this.ready = true,
  });

  final String id;
  final String name;
  final SiteKind kind;
  final List<SiteTag> tags;
  final int color;
  final String letter;
  /// Primary first; failover order for page hosts.
  final List<String> mirrors;
  final bool searchable;
  final bool ready;

  String get primaryHost =>
      mirrors.isNotEmpty ? mirrors.first : 'https://example.com';
}

class SourceCatalog {
  SourceCatalog._();

  static const pornhub = SiteDef(
    id: 'pornhub',
    name: 'Pornhub',
    kind: SiteKind.video,
    color: 0xFFFF9000,
    letter: 'P',
    mirrors: [
      'https://www.pornhub.com',
      'https://www.pornhub.org',
      'https://cn.pornhub.com',
      'https://rt.pornhub.com',
      'https://de.pornhub.com',
      'https://fr.pornhub.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        feedKind: VideoFeedKind.hot,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        feedKind: VideoFeedKind.asian,
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        feedKind: VideoFeedKind.hot,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'rec',
        label: '推',
        feedKind: VideoFeedKind.hot,
        icon: Icons.recommend_outlined,
        iconSelected: Icons.recommend,
      ),
    ],
  );

  static const xvideos = SiteDef(
    id: 'xvideos',
    name: 'XVideos',
    kind: SiteKind.video,
    color: 0xFFC41E3A,
    letter: 'X',
    mirrors: [
      'https://www.xvideos.com',
      'https://www.xvideos.es',
      'https://www.xvideos.net',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        feedKind: VideoFeedKind.x,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        feedKind: VideoFeedKind.x,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        feedKind: VideoFeedKind.x,
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'best',
        label: '榜',
        feedKind: VideoFeedKind.x,
        icon: Icons.emoji_events_outlined,
        iconSelected: Icons.emoji_events,
      ),
    ],
  );

  static const mitao = SiteDef(
    id: 'mitao',
    name: '中文字幕',
    kind: SiteKind.video,
    color: 0xFFE91E63,
    letter: '中',
    mirrors: [
      'https://mitaohk.com',
      'https://www.mitaohk.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'sub',
        label: '中',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.subtitles_outlined,
        iconSelected: Icons.subtitles,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'rec',
        label: '推',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.recommend_outlined,
        iconSelected: Icons.recommend,
      ),
    ],
  );

  static const xnxx = SiteDef(
    id: 'xnxx',
    name: 'XNXX',
    kind: SiteKind.video,
    color: 0xFF1565C0,
    letter: 'N',
    ready: false,
    mirrors: [
      'https://www.xnxx.com',
      'https://www.xnxx.tv',
      'https://www.xnxx.es',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'best',
        label: '榜',
        icon: Icons.emoji_events_outlined,
        iconSelected: Icons.emoji_events,
      ),
    ],
  );

  static const xhamster = SiteDef(
    id: 'xhamster',
    name: 'xHamster',
    kind: SiteKind.video,
    color: 0xFF6A1B9A,
    letter: 'H',
    ready: false,
    mirrors: [
      'https://xhamster.com',
      'https://xhamster.desi',
      'https://xhamster2.com',
      'https://zh.xhamster.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'best',
        label: '榜',
        icon: Icons.emoji_events_outlined,
        iconSelected: Icons.emoji_events,
      ),
    ],
  );

  static const eporner = SiteDef(
    id: 'eporner',
    name: 'Eporner',
    kind: SiteKind.video,
    color: 0xFF00897B,
    letter: 'E',
    ready: false,
    mirrors: [
      'https://www.eporner.com',
      'https://eporner.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'best',
        label: '榜',
        icon: Icons.emoji_events_outlined,
        iconSelected: Icons.emoji_events,
      ),
    ],
  );

  static const stripchat = SiteDef(
    id: 'stripchat',
    name: 'Stripchat',
    kind: SiteKind.live,
    color: 0xFFD32F2F,
    letter: 'S',
    searchable: false,
    ready: false,
    mirrors: [
      'https://stripchat.com',
      'https://zh.stripchat.com',
      'https://stripchat.global',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asia',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'tag',
        label: '标',
        icon: Icons.sell_outlined,
        iconSelected: Icons.sell,
      ),
    ],
  );

  static const chaturbate = SiteDef(
    id: 'chaturbate',
    name: 'Chaturbate',
    kind: SiteKind.live,
    color: 0xFFF57C00,
    letter: 'C',
    searchable: false,
    ready: false,
    mirrors: [
      'https://chaturbate.com',
      'https://zh.chaturbate.com',
      'https://chaturbate.eu',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asia',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'tag',
        label: '标',
        icon: Icons.sell_outlined,
        iconSelected: Icons.sell,
      ),
    ],
  );

  static const our55 = SiteDef(
    id: 'our55',
    name: 'Our55',
    kind: SiteKind.video,
    color: 0xFF455A64,
    letter: 'O',
    ready: false,
    mirrors: [
      'https://74214.our55.xyz',
      'https://our55.xyz',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'rec',
        label: '推',
        icon: Icons.recommend_outlined,
        iconSelected: Icons.recommend,
      ),
    ],
  );

  static const xqq88 = SiteDef(
    id: 'xqq88',
    name: '88XQQ',
    kind: SiteKind.video,
    color: 0xFF5D4037,
    letter: '8',
    ready: false,
    mirrors: [
      'https://www.88xqq.com',
      'https://88xqq.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '热',
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '新',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '亚',
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'rec',
        label: '推',
        icon: Icons.recommend_outlined,
        iconSelected: Icons.recommend,
      ),
    ],
  );

  static const all = <SiteDef>[
    pornhub,
    xvideos,
    mitao,
    xnxx,
    xhamster,
    eporner,
    our55,
    xqq88,
    stripchat,
    chaturbate,
  ];

  static SiteDef? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static List<SiteDef> get videoSites =>
      all.where((s) => s.kind == SiteKind.video).toList();

  static List<SiteDef> get liveSites =>
      all.where((s) => s.kind == SiteKind.live).toList();

  /// All video sites on home by default (preview list).
  static List<String> get defaultEnabledVideoIds =>
      videoSites.map((s) => s.id).toList();

  static const defaultLiveId = 'stripchat';
}
