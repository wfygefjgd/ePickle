import '../models/feed_kind.dart';

/// Built-in site directory. Adapters fill data later; PH / X / 中 already wired.
enum SiteKind { video, live }

class SiteTag {
  const SiteTag({
    required this.id,
    required this.label,
    this.feedKind,
  });

  final String id;
  final String label;
  /// Maps to existing fetch path; null = placeholder / same as first.
  final VideoFeedKind? feedKind;
}

class SiteDef {
  const SiteDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.tags,
    required this.color,
    required this.letter,
    this.searchable = true,
    this.ready = true,
  });

  final String id;
  final String name;
  final SiteKind kind;
  final List<SiteTag> tags;
  final int color;
  final String letter;
  final bool searchable;
  final bool ready;
}

class SourceCatalog {
  SourceCatalog._();

  static const pornhub = SiteDef(
    id: 'pornhub',
    name: 'Pornhub',
    kind: SiteKind.video,
    color: 0xFFFF9000,
    letter: 'P',
    tags: [
      SiteTag(id: 'hot', label: '热门', feedKind: VideoFeedKind.hot),
      SiteTag(id: 'asian', label: '亚', feedKind: VideoFeedKind.asian),
      SiteTag(id: 'new', label: '新', feedKind: VideoFeedKind.hot),
      SiteTag(id: 'rec', label: '推', feedKind: VideoFeedKind.hot),
    ],
  );

  static const xvideos = SiteDef(
    id: 'xvideos',
    name: 'XVideos',
    kind: SiteKind.video,
    color: 0xFFC41E3A,
    letter: 'X',
    tags: [
      SiteTag(id: 'hot', label: '热门', feedKind: VideoFeedKind.x),
      SiteTag(id: 'new', label: '新', feedKind: VideoFeedKind.x),
      SiteTag(id: 'asian', label: '亚', feedKind: VideoFeedKind.x),
      SiteTag(id: 'best', label: '榜', feedKind: VideoFeedKind.x),
    ],
  );

  static const mitao = SiteDef(
    id: 'mitao',
    name: '中文字幕',
    kind: SiteKind.video,
    color: 0xFFE91E63,
    letter: '中',
    tags: [
      SiteTag(id: 'hot', label: '热门', feedKind: VideoFeedKind.zhong),
      SiteTag(id: 'sub', label: '中', feedKind: VideoFeedKind.zhong),
      SiteTag(id: 'new', label: '新', feedKind: VideoFeedKind.zhong),
      SiteTag(id: 'rec', label: '推', feedKind: VideoFeedKind.zhong),
    ],
  );

  static const xnxx = SiteDef(
    id: 'xnxx',
    name: 'XNXX',
    kind: SiteKind.video,
    color: 0xFF1565C0,
    letter: 'N',
    ready: false,
    tags: [
      SiteTag(id: 'hot', label: '热门'),
      SiteTag(id: 'new', label: '新'),
      SiteTag(id: 'asian', label: '亚'),
      SiteTag(id: 'best', label: '榜'),
    ],
  );

  static const xhamster = SiteDef(
    id: 'xhamster',
    name: 'xHamster',
    kind: SiteKind.video,
    color: 0xFF6A1B9A,
    letter: 'H',
    ready: false,
    tags: [
      SiteTag(id: 'hot', label: '热门'),
      SiteTag(id: 'new', label: '新'),
      SiteTag(id: 'asian', label: '亚'),
      SiteTag(id: 'best', label: '榜'),
    ],
  );

  static const eporner = SiteDef(
    id: 'eporner',
    name: 'Eporner',
    kind: SiteKind.video,
    color: 0xFF00897B,
    letter: 'E',
    ready: false,
    tags: [
      SiteTag(id: 'hot', label: '热门'),
      SiteTag(id: 'new', label: '新'),
      SiteTag(id: 'asian', label: '亚'),
      SiteTag(id: 'best', label: '榜'),
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
    tags: [
      SiteTag(id: 'hot', label: '热门'),
      SiteTag(id: 'new', label: '新'),
      SiteTag(id: 'asia', label: '亚'),
      SiteTag(id: 'tag', label: '标'),
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
    tags: [
      SiteTag(id: 'hot', label: '热门'),
      SiteTag(id: 'new', label: '新'),
      SiteTag(id: 'asia', label: '亚'),
      SiteTag(id: 'tag', label: '标'),
    ],
  );

  static const all = <SiteDef>[
    pornhub,
    xvideos,
    mitao,
    xnxx,
    xhamster,
    eporner,
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

  /// Default home list (video only).
  static const defaultEnabledVideoIds = ['pornhub', 'xvideos', 'mitao'];

  static const defaultLiveId = 'stripchat';
}
