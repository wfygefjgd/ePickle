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
    final host = Uri.tryParse(u)?.host ?? u;
    final letter = host.isNotEmpty ? host[0].toUpperCase() : '?';
    return SiteDef(
      id: 'custom_$host',
      name: host,
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
    name: '\u4e2d\u6587\u5b57\u5e55',
    kind: SiteKind.video,
    color: 0xFFE91E63,
    letter: '\u4e2d',
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

  static const eporner = SiteDef(
    id: 'eporner',
    name: 'Eporner',
    kind: SiteKind.video,
    color: 0xFF00897B,
    letter: 'E',
    ready: true,
    mirrors: [
      'https://www.eporner.com',
      'https://eporner.com',
    ],
    tags: vodTags,
  );

  static const freeporn = SiteDef(
    id: 'freeporn',
    name: 'FreePorn',
    kind: SiteKind.video,
    color: 0xFFE65100,
    letter: 'F',
    ready: true,
    mirrors: [
      'https://www.freeporn.com',
      'https://freeporn.com',
    ],
    tags: vodTags,
  );

  static const spankbang = SiteDef(
    id: 'spankbang',
    name: 'SpankBang',
    kind: SiteKind.video,
    color: 0xFFC62828,
    letter: 'B',
    ready: true,
    mirrors: [
      'https://spankbang.com',
      'https://www.spankbang.com',
      'https://spankbang.party',
    ],
    tags: vodTags,
  );

  static const youporn = SiteDef(
    id: 'youporn',
    name: 'YouPorn',
    kind: SiteKind.video,
    color: 0xFFAD1457,
    letter: 'Y',
    ready: true,
    mirrors: [
      'https://www.youporn.com',
      'https://youporn.com',
    ],
    tags: vodTags,
  );

  static const redtube = SiteDef(
    id: 'redtube',
    name: 'RedTube',
    kind: SiteKind.video,
    color: 0xFFB71C1C,
    letter: 'R',
    ready: true,
    mirrors: [
      'https://www.redtube.com',
      'https://redtube.com',
    ],
    tags: vodTags,
  );

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

  static const javmix = SiteDef(
    id: 'javmix',
    name: 'JAVMix',
    kind: SiteKind.video,
    color: 0xFF00695C,
    letter: 'J',
    ready: true,
    mirrors: [
      'https://javmix.tv',
      'https://www.javmix.tv',
    ],
    tags: vodTags,
  );

  static const javgg = SiteDef(
    id: 'javgg',
    name: 'JavGG',
    kind: SiteKind.video,
    color: 0xFF283593,
    letter: 'G',
    ready: true,
    mirrors: [
      'https://javgg.net',
      'https://www.javgg.net',
    ],
    tags: vodTags,
  );

  static const av01 = SiteDef(
    id: 'av01',
    name: 'AV01',
    kind: SiteKind.video,
    color: 0xFF37474F,
    letter: 'A',
    ready: true,
    mirrors: [
      'https://www.av01.media',
      'https://www.av01.media/jp',
      'https://av01.media',
    ],
    tags: vodTags,
  );

  static const missav = SiteDef(
    id: 'missav',
    name: 'MissAV',
    kind: SiteKind.video,
    color: 0xFF880E4F,
    letter: 'M',
    ready: true,
    mirrors: [
      'https://missav.ai',
      'https://missav.ai/dm247/cn',
      'https://missav.ws',
      'https://missav.com',
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
    ],
    tags: vodTags,
  );

  static const mmtv7 = SiteDef(
    id: '7mmtv',
    name: '7MMTV',
    kind: SiteKind.video,
    color: 0xFFBF360C,
    letter: '7',
    ready: true,
    mirrors: [
      'https://7mmtv.sx',
      'https://www.7mmtv.sx',
    ],
    tags: vodTags,
  );

  static const bestjavporn = SiteDef(
    id: 'bestjavporn',
    name: 'BestJAVPorn',
    kind: SiteKind.video,
    color: 0xFF33691E,
    letter: 'B',
    ready: true,
    mirrors: [
      'https://www.bestjavporn.com',
      'https://www.bestjavporn.com/zh',
      'https://bestjavporn.com',
    ],
    tags: vodTags,
  );

  static const our55 = SiteDef(
    id: 'our55',
    name: 'Our55',
    kind: SiteKind.video,
    color: 0xFF455A64,
    letter: 'O',
    ready: true,
    mirrors: [
      'https://74214.our55.xyz',
      'https://our55.xyz',
    ],
    tags: vodTags,
  );

  static const xqq88 = SiteDef(
    id: 'xqq88',
    name: '88XQQ',
    kind: SiteKind.video,
    color: 0xFF5D4037,
    letter: '8',
    ready: true,
    mirrors: [
      'https://www.88xqq.com',
      'https://88xqq.com',
    ],
    tags: vodTags,
  );

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
    ],
    tags: liveTags,
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
    ],
    tags: liveTags,
  );

  static const all = <SiteDef>[
    pornhub,
    xvideos,
    mitao,
    xnxx,
    xhamster,
    eporner,
    freeporn,
    spankbang,
    youporn,
    redtube,
    tnaflix,
    javmix,
    javgg,
    av01,
    missav,
    jable,
    mmtv7,
    bestjavporn,
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

  static List<String> get defaultEnabledVideoIds =>
      videoSites.map((s) => s.id).toList();

  static const defaultLiveId = 'stripchat';
}
