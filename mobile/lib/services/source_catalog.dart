import 'package:flutter/material.dart';

import '../models/feed_kind.dart';

/// Built-in site directory. Adapters fill data later; PH / X / zhong already wired.
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
    this.custom = false,
  });

  final String id;
  final String name;
  final SiteKind kind;
  final List<SiteTag> tags;
  final int color;
  final String letter;
  final List<String> mirrors;
  final bool searchable;
  final bool ready;
  final bool custom;

  String get primaryHost =>
      mirrors.isNotEmpty ? mirrors.first : 'https://example.com';

  factory SiteDef.customFromUrl(String url) {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(u);
    final host = uri?.host ?? u;
    final displayName = uri == null
        ? host
        : '${uri.authority}${uri.path == '/' ? '' : uri.path}';
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return SiteDef(
      id: 'custom_${Uri.encodeComponent(u)}',
      name: displayName,
      kind: SiteKind.video,
      color: 0xFF607D8B,
      letter: letter,
      mirrors: [u.startsWith('http') ? u : 'https://$u'],
      tags: SourceCatalog.vodTags,
      ready: true,
      custom: true,
    );
  }
}

class SourceCatalog {
  SourceCatalog._();

  // Chinese short labels via \u escapes (avoid file encoding breakage).
  static const vodTags = <SiteTag>[
    SiteTag(
      id: 'hot',
      label: '\u70ed',
      icon: Icons.local_fire_department_outlined,
      iconSelected: Icons.local_fire_department,
    ),
    SiteTag(
      id: 'new',
      label: '\u65b0',
      icon: Icons.fiber_new_outlined,
      iconSelected: Icons.fiber_new,
    ),
    SiteTag(
      id: 'asian',
      label: '\u4e9a',
      icon: Icons.public_outlined,
      iconSelected: Icons.public,
    ),
    SiteTag(
      id: 'best',
      label: '\u699c',
      icon: Icons.emoji_events_outlined,
      iconSelected: Icons.emoji_events,
    ),
  ];

  static const liveTags = <SiteTag>[
    SiteTag(
      id: 'hot',
      label: '\u70ed',
      icon: Icons.local_fire_department_outlined,
      iconSelected: Icons.local_fire_department,
    ),
    SiteTag(
      id: 'new',
      label: '\u65b0',
      icon: Icons.fiber_new_outlined,
      iconSelected: Icons.fiber_new,
    ),
    SiteTag(
      id: 'asia',
      label: '\u4e9a',
      icon: Icons.public_outlined,
      iconSelected: Icons.public,
    ),
    SiteTag(
      id: 'tag',
      label: '\u6807',
      icon: Icons.sell_outlined,
      iconSelected: Icons.sell,
    ),
  ];

  static const chaturbateTags = <SiteTag>[
    SiteTag(
        id: 'female',
        label: '\u5973',
        icon: Icons.woman_outlined,
        iconSelected: Icons.woman),
    SiteTag(
        id: 'couples',
        label: '\u4f34',
        icon: Icons.people_outline,
        iconSelected: Icons.people),
    SiteTag(
        id: 'new',
        label: '\u65b0',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new),
    SiteTag(
        id: 'asian',
        label: '\u4e9a',
        icon: Icons.public_outlined,
        iconSelected: Icons.public),
  ];

  static const stripchatTags = <SiteTag>[
    SiteTag(
        id: 'girls',
        label: '\u5973',
        icon: Icons.woman_outlined,
        iconSelected: Icons.woman),
    SiteTag(
        id: 'new',
        label: '\u65b0',
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new),
    SiteTag(
        id: 'couples',
        label: '\u4f34',
        icon: Icons.people_outline,
        iconSelected: Icons.people),
    SiteTag(
        id: 'more',
        label: '\u4e9a',
        icon: Icons.public_outlined,
        iconSelected: Icons.public),
  ];

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
        label: '\u70ed',
        feedKind: VideoFeedKind.hot,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'asian',
        label: '\u4e9a',
        feedKind: VideoFeedKind.asian,
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'new',
        label: '\u65b0',
        feedKind: VideoFeedKind.hot,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'rec',
        label: '\u63a8',
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
        label: '\u70ed',
        feedKind: VideoFeedKind.x,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'new',
        label: '\u65b0',
        feedKind: VideoFeedKind.x,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'asian',
        label: '\u4e9a',
        feedKind: VideoFeedKind.x,
        icon: Icons.public_outlined,
        iconSelected: Icons.public,
      ),
      SiteTag(
        id: 'best',
        label: '\u699c',
        feedKind: VideoFeedKind.x,
        icon: Icons.emoji_events_outlined,
        iconSelected: Icons.emoji_events,
      ),
    ],
  );

  static const mitao = SiteDef(
    id: 'mitao',
    name: 'mitaohk.com',
    kind: SiteKind.video,
    color: 0xFFE91E63,
    letter: 'M',
    mirrors: [
      'https://mitaohk.com',
      'https://www.mitaohk.com',
    ],
    tags: [
      SiteTag(
        id: 'hot',
        label: '\u70ed',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.local_fire_department_outlined,
        iconSelected: Icons.local_fire_department,
      ),
      SiteTag(
        id: 'sub',
        label: '\u4e2d',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.subtitles_outlined,
        iconSelected: Icons.subtitles,
      ),
      SiteTag(
        id: 'new',
        label: '\u65b0',
        feedKind: VideoFeedKind.zhong,
        icon: Icons.fiber_new_outlined,
        iconSelected: Icons.fiber_new,
      ),
      SiteTag(
        id: 'rec',
        label: '\u63a8',
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
    ready: true,
    mirrors: [
      'https://www.xnxx.com',
      'https://www.xnxx.tv',
      'https://www.xnxx.es',
    ],
    tags: vodTags,
  );

  static const xhamster = SiteDef(
    id: 'xhamster',
    name: 'xHamster',
    kind: SiteKind.video,
    color: 0xFF6A1B9A,
    letter: 'H',
    ready: true,
    mirrors: [
      'https://xhamster.com',
      'https://xhamster.desi',
      'https://xhamster2.com',
      'https://zh.xhamster.com',
    ],
    tags: vodTags,
  );

  // Removed from catalog (unstable / blocked for most users):
  // eporner, freeporn, spankbang, youporn, redtube, javmix, javgg,
  // av01, missav, 7mmtv, bestjavporn.

  static const tnaflix = SiteDef(
    id: 'tnaflix',
    name: 'TNAFlix',
    kind: SiteKind.video,
    color: 0xFF4A148C,
    letter: 'T',
    ready: true,
    mirrors: [
      'https://www.tnaflix.com',
      'https://tnaflix.com',
    ],
    tags: vodTags,
  );

  static const jable = SiteDef(
    id: 'jable',
    name: 'Jable',
    kind: SiteKind.video,
    color: 0xFF1A237E,
    letter: 'J',
    ready: true,
    mirrors: [
      'https://jable.tv',
      'https://www.jable.tv',
      'https://jable.one',
    ],
    tags: vodTags,
  );

  // Removed: our55, xqq88 (unstable for users).

  static const stripchat = SiteDef(
    id: 'stripchat',
    name: 'Stripchat',
    kind: SiteKind.live,
    color: 0xFFD32F2F,
    letter: 'S',
    searchable: false,
    ready: true,
    mirrors: [
      'https://zh.stripchat.com',
      'https://stripchat.com',
      'https://www.stripchat.com',
      'https://stripchat.global',
      'https://xhamsterlive.com',
    ],
    tags: stripchatTags,
  );

  static const chaturbate = SiteDef(
    id: 'chaturbate',
    name: 'Chaturbate',
    kind: SiteKind.live,
    color: 0xFFF57C00,
    letter: 'C',
    searchable: false,
    ready: true,
    mirrors: [
      'https://chaturbate.com',
      'https://www.chaturbate.com',
      'https://zh.chaturbate.com',
      'https://chaturbate.eu',
      'https://chaturbate.global',
    ],
    tags: chaturbateTags,
  );

  static const all = <SiteDef>[
    pornhub,
    xvideos,
    mitao,
    xnxx,
    xhamster,
    tnaflix,
    jable,
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

  static List<String> get defaultEnabledVideoIds =>
      videoSites.where((s) => s.ready).map((s) => s.id).toList();

  /// The first three VOD adapters randomize internally. Remaining VOD sites
  /// use generic random pages; live channels must stay ordered and stable.
  static bool usesRandomizedGenericFeed(SiteDef site) =>
      site.kind == SiteKind.video &&
      site.id != 'pornhub' &&
      site.id != 'xvideos' &&
      site.id != 'mitao';

  static const defaultLiveId = 'chaturbate';
}
