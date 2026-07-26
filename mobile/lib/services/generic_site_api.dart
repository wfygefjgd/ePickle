import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import '../utils/http_client.dart';
import '../utils/http_headers.dart';
import 'phub_api.dart';
import 'source_catalog.dart';

/// Generic HTML scraper with mirror failover for tube / JAV-style sites.
class GenericSiteApi {
  GenericSiteApi({Dio? dio})
      : _dio = dio ??
            AppHttpClient.create(
              headers: {
                ...AppHttpHeaders.browser,
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
              },
              connectTimeout: const Duration(seconds: 14),
              receiveTimeout: const Duration(seconds: 22),
            );

  final Dio _dio;

  /// Per-site last working mirror index (in-memory).
  final Map<String, int> _mirrorIndex = {};

  Future<String> _getHtml(String url, {Map<String, String>? headers}) async {
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode == 403) {
      throw PhubException('访问被拒绝 (403)');
    }
    if (res.statusCode == 404) {
      throw PhubException('页面不存在 (404)');
    }
    if (res.data == null || res.data!.isEmpty) {
      throw PhubException('空响应');
    }
    return res.data!;
  }

  List<String> _mirrorsFor(SiteDef site) {
    if (site.mirrors.isNotEmpty) return List<String>.from(site.mirrors);
    return [site.primaryHost];
  }

  String _abs(String base, String path) {
    final p = path.trim();
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('//')) return 'https:$p';
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    if (p.startsWith('/')) return '$b$p';
    return '$b/$p';
  }

  Future<String> _fetchWithMirrors(
    SiteDef site,
    String Function(String base) pathBuilder, {
    Map<String, String>? extraHeaders,
  }) async {
    final mirrors = _mirrorsFor(site);
    final start = (_mirrorIndex[site.id] ?? 0).clamp(0, mirrors.length - 1);
    Object? lastErr;
    for (var n = 0; n < mirrors.length; n++) {
      final i = (start + n) % mirrors.length;
      final base = mirrors[i].replaceAll(RegExp(r'/$'), '');
      final url = pathBuilder(base);
      try {
        final headers = <String, String>{
          ...AppHttpHeaders.browser,
          'Referer': '$base/',
          'Origin': base,
          if (extraHeaders != null) ...extraHeaders,
        };
        final html = await _getHtml(url, headers: headers);
        if (html.length < 400) {
          lastErr = PhubException('页面过短');
          continue;
        }
        // Soft block pages
        final low = html.toLowerCase();
        if (low.contains('just a moment') && low.contains('cloudflare')) {
          lastErr = PhubException('Cloudflare 拦截');
          continue;
        }
        _mirrorIndex[site.id] = i;
        return html;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? PhubException('所有镜像均失败：${site.name}');
  }

  /// Feed list for a site tag (hot/new/asian/best).
  Future<List<VideoItem>> fetchFeed(
    SiteDef site, {
    String tagId = 'hot',
    int limit = 40,
    Set<String>? exclude,
  }) async {
    final paths = _listPaths(site, tagId);
    final seen = <String>{...?exclude};
    final results = <VideoItem>[];
    final rng = Random();

    for (final pathFn in paths) {
      if (results.length >= limit) break;
      try {
        final html = await _fetchWithMirrors(site, pathFn);
        final base = _mirrorsFor(site)[_mirrorIndex[site.id] ?? 0]
            .replaceAll(RegExp(r'/$'), '');
        results.addAll(_parseList(html, base, seen, site));
      } catch (_) {
        continue;
      }
    }

    if (results.isEmpty) {
      throw PhubException(
        '无法从 ${site.name} 获取列表。\n请确认网络/代理，或该站结构有变。',
      );
    }
    results.shuffle(rng);
    if (results.length > limit) return results.sublist(0, limit);
    return results;
  }

  Future<List<VideoItem>> search(
    SiteDef site,
    String query, {
    int page = 1,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final enc = Uri.encodeQueryComponent(q);
    final paths = _searchPaths(site, enc, page);
    final seen = <String>{};
    for (final pathFn in paths) {
      try {
        final html = await _fetchWithMirrors(site, pathFn);
        final base = _mirrorsFor(site)[_mirrorIndex[site.id] ?? 0]
            .replaceAll(RegExp(r'/$'), '');
        final list = _parseList(html, base, seen, site);
        if (list.isNotEmpty) return list;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  Future<VideoDetail> getVideoDetail(SiteDef site, String url) async {
    final base = _originOf(url) ??
        _mirrorsFor(site)[_mirrorIndex[site.id] ?? 0]
            .replaceAll(RegExp(r'/$'), '');
    String html;
    try {
      html = await _getHtml(
        url,
        headers: {
          ...AppHttpHeaders.browser,
          'Referer': '$base/',
          'Origin': base,
        },
      );
    } catch (_) {
      // Retry via mirrors with path only
      final path = Uri.tryParse(url)?.path ?? url;
      html = await _fetchWithMirrors(site, (b) => '$b$path');
    }

    final title = _extractTitle(html) ?? url;
    final thumb = _extractThumb(html);
    final streams = _extractStreams(html, base);
    if (streams.isEmpty) {
      throw PhubException('无法解析播放地址：${site.name}');
    }
    streams.sort((a, b) => b.pixels.compareTo(a.pixels));
    return VideoDetail(
      url: url,
      title: title,
      durationSec: 0,
      thumb: thumb,
      streams: streams,
    );
  }

  /// Custom user URL: treat host as one-off site.
  Future<List<VideoItem>> fetchCustomHost(
    String baseUrl, {
    int limit = 40,
    Set<String>? exclude,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final host = Uri.tryParse(base)?.host ?? base;
    final fake = SiteDef(
      id: 'custom_$host',
      name: host,
      kind: SiteKind.video,
      color: 0xFF607D8B,
      letter: host.isNotEmpty ? host[0].toUpperCase() : '?',
      mirrors: [base],
      tags: const [],
      ready: true,
    );
    return fetchFeed(fake, limit: limit, exclude: exclude);
  }

  Future<VideoDetail> getCustomDetail(String pageUrl) async {
    final origin = _originOf(pageUrl) ?? pageUrl;
    final host = Uri.tryParse(origin)?.host ?? 'custom';
    final fake = SiteDef(
      id: 'custom_$host',
      name: host,
      kind: SiteKind.video,
      color: 0xFF607D8B,
      letter: 'C',
      mirrors: [origin],
      tags: const [],
      ready: true,
    );
    return getVideoDetail(fake, pageUrl);
  }

  String? _originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return null;
    return '${u.scheme}://${u.host}';
  }

  List<String Function(String base)> _listPaths(SiteDef site, String tagId) {
    final id = site.id;
    // Site-specific first paths
    switch (id) {
      case 'xnxx':
        return [
          if (tagId == 'new') (b) => '$b/search/new',
          if (tagId == 'asian') (b) => '$b/?k=asian',
          if (tagId == 'best') (b) => '$b/best',
          (b) => '$b/',
          (b) => '$b/hits',
          (b) => '$b/search/hot',
        ];
      case 'xhamster':
        return [
          if (tagId == 'new') (b) => '$b/newest',
          if (tagId == 'asian') (b) => '$b/categories/asian',
          if (tagId == 'best') (b) => '$b/best',
          (b) => '$b/',
          (b) => '$b/hottest',
        ];
      case 'eporner':
        return [
          if (tagId == 'new') (b) => '$b/recent/',
          if (tagId == 'asian') (b) => '$b/cat/asian/',
          if (tagId == 'best') (b) => '$b/top/',
          (b) => '$b/',
          (b) => '$b/best-videos/',
        ];
      case 'spankbang':
        return [
          if (tagId == 'new') (b) => '$b/new_videos/',
          if (tagId == 'asian') (b) => '$b/s/asian/',
          if (tagId == 'best') (b) => '$b/trending_videos/',
          (b) => '$b/',
        ];
      case 'youporn':
        return [
          if (tagId == 'new') (b) => '$b/?page=1',
          if (tagId == 'asian') (b) => '$b/category/asian/',
          (b) => '$b/',
          (b) => '$b/popular/',
        ];
      case 'redtube':
        return [
          if (tagId == 'new') (b) => '$b/?page=1',
          if (tagId == 'asian') (b) => '$b/redtube/asian',
          (b) => '$b/',
        ];
      case 'tnaflix':
        return [
          (b) => '$b/',
          (b) => '$b/new',
          (b) => '$b/popular',
        ];
      case 'freeporn':
        return [
          (b) => '$b/',
          (b) => '$b/videos',
        ];
      case 'jable':
        return [
          if (tagId == 'new') (b) => '$b/latest-updates/',
          if (tagId == 'asian') (b) => '$b/categories/chinese-subtitle/',
          (b) => '$b/',
          (b) => '$b/hot/',
          (b) => '$b/categories/uncensored-leak/',
        ];
      case 'missav':
        return [
          if (tagId == 'new') (b) => '$b/dm22/new',
          if (tagId == 'asian') (b) => '$b/dm247/cn',
          (b) => '$b/dm22/new',
          (b) => '$b/',
          (b) => '$b/dm247/cn',
        ];
      case 'javgg':
        return [
          (b) => '$b/',
          (b) => '$b/genre/uncensored/',
          (b) => '$b/new-post/',
        ];
      case 'javmix':
        return [
          (b) => '$b/',
          (b) => '$b/genre/uncensored',
        ];
      case 'av01':
        return [
          (b) => '$b/jp',
          (b) => '$b/',
          (b) => '$b/jp/latest',
        ];
      case '7mmtv':
        return [
          (b) => '$b/',
          (b) => '$b/zh',
          (b) => '$b/en',
        ];
      case 'bestjavporn':
        return [
          (b) => '$b/zh/',
          (b) => '$b/',
          (b) => '$b/zh/new/',
        ];
      case 'our55':
      case 'xqq88':
        return [
          (b) => '$b/',
          (b) => '$b/home.html',
          (b) => '$b/index.html',
          (b) => '$b/index.php',
        ];
      case 'stripchat':
      case 'chaturbate':
        return [
          (b) => '$b/',
          (b) => '$b/female-cams',
          (b) => '$b/tags/asian',
        ];
      default:
        return [
          (b) => '$b/',
          (b) => '$b/videos',
          (b) => '$b/new',
          (b) => '$b/popular',
        ];
    }
  }

  List<String Function(String base)> _searchPaths(
    SiteDef site,
    String enc,
    int page,
  ) {
    final p = page < 1 ? 1 : page;
    switch (site.id) {
      case 'xnxx':
        return [
          (b) => '$b/search/$enc${p > 1 ? '/$p' : ''}',
          (b) => '$b/?k=$enc',
        ];
      case 'xhamster':
        return [
          (b) => '$b/search/$enc${p > 1 ? '?page=$p' : ''}',
        ];
      case 'eporner':
        return [
          (b) => '$b/search/$enc/${p > 1 ? '$p/' : ''}',
        ];
      case 'spankbang':
        return [
          (b) => '$b/s/$enc/${p > 1 ? '$p/' : ''}',
        ];
      case 'jable':
        return [
          (b) => '$b/search/$enc/',
        ];
      case 'missav':
        return [
          (b) => '$b/search/$enc',
        ];
      default:
        return [
          (b) => '$b/search?q=$enc&page=$p',
          (b) => '$b/search/$enc',
          (b) => '$b/?s=$enc',
          (b) => '$b/search.html?wd=$enc',
        ];
    }
  }

  List<VideoItem> _parseList(
    String html,
    String base,
    Set<String> seen,
    SiteDef site,
  ) {
    final out = <VideoItem>[];
    // Collect href candidates that look like video pages
    final hrefRe = RegExp(
      r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final titleRe = RegExp(
      r'''(?:title|alt)\s*=\s*["']([^"']{3,200})["']''',
      caseSensitive: false,
    );
    final imgRe = RegExp(
      r'''(?:data-src|data-original|data-thumb|data-poster|src)\s*=\s*["']((?:https?:)?//[^"']+\.(?:jpg|jpeg|png|webp|gif)[^"']*|[^"']+/thumb[^"']*|[^"']+/cover[^"']*)["']''',
      caseSensitive: false,
    );

    // Split into rough cards by common wrappers
    var chunks = html.split(RegExp(
      r'(?=<div[^>]+class="[^"]*(?:video|thumb|item|card|post|movie|list-item)[^"]*")',
      caseSensitive: false,
    ));
    if (chunks.length < 3) {
      chunks = html.split(RegExp(r'''(?=href=["'][^"']+["'])'''));
    }

    for (final chunk in chunks) {
      if (chunk.length < 40 || chunk.length > 12000) continue;
      String? href;
      for (final m in hrefRe.allMatches(chunk)) {
        final h = m.group(1)!;
        if (_looksLikeVideoPath(h, site)) {
          href = h;
          break;
        }
      }
      if (href == null) continue;
      final abs = _abs(base, href);
      final key = abs.split('#').first.split('?').first;
      if (!seen.add(key)) continue;

      String? title;
      final tm = titleRe.firstMatch(chunk);
      if (tm != null) {
        title = _cleanTitle(tm.group(1)!);
      }
      if (title == null || title.length < 2) {
        final aText = RegExp(
          r'>\s*([^<>]{4,120})\s*<',
        ).firstMatch(chunk);
        if (aText != null) title = _cleanTitle(aText.group(1)!);
      }
      if (title == null || title.length < 2) {
        final slug = key.split('/').where((e) => e.isNotEmpty).last;
        title = Uri.decodeComponent(slug)
            .replaceAll(RegExp(r'[-_]+'), ' ')
            .trim();
      }
      if (title.length < 2) continue;
      if (_isJunkTitle(title)) continue;

      String? thumb;
      final im = imgRe.firstMatch(chunk);
      if (im != null) {
        thumb = im.group(1);
        if (thumb != null && thumb.startsWith('//')) thumb = 'https:$thumb';
        if (thumb != null && !thumb.startsWith('http')) {
          thumb = _abs(base, thumb);
        }
      }

      out.add(VideoItem(
        url: abs,
        title: title,
        duration: '-',
        thumb: thumb,
      ));
      if (out.length >= 80) break;
    }
    return out;
  }

  bool _looksLikeVideoPath(String href, SiteDef site) {
    final h = href.toLowerCase();
    if (h.startsWith('javascript:') ||
        h.startsWith('#') ||
        h.startsWith('mailto:') ||
        h.contains('login') ||
        h.contains('signup') ||
        h.contains('register') ||
        h.contains('/tag/') ||
        h.contains('/tags/') ||
        h.contains('/category/') ||
        h.contains('/categories/') ||
        h.contains('/search') ||
        h.endsWith('.css') ||
        h.endsWith('.js')) {
      return false;
    }
    // Positive patterns
    if (RegExp(r'/video[s./]').hasMatch(h)) return true;
    if (RegExp(r'/v/\d').hasMatch(h)) return true;
    if (RegExp(r'/watch').hasMatch(h)) return true;
    if (RegExp(r'/view_video').hasMatch(h)) return true;
    if (RegExp(r'/embed/').hasMatch(h)) return true;
    if (RegExp(r'/(movies?|clips?)/').hasMatch(h)) return true;
    if (RegExp(r'/\d{4,}/').hasMatch(h) && h.split('/').length >= 3) {
      return true;
    }
    // JAV style /xx/CODE-123/
    if (RegExp(r'/[a-z]{2,10}-\d{2,5}').hasMatch(h)) return true;
    if (RegExp(r'/(uncensored|censored)/').hasMatch(h)) return true;
    // Live rooms
    if (site.kind == SiteKind.live) {
      if (RegExp(r'/[^/]{3,40}/?$').hasMatch(h) && !h.contains('.')) {
        return true;
      }
    }
    return false;
  }

  String _cleanTitle(String t) {
    return t
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isJunkTitle(String t) {
    final low = t.toLowerCase();
    if (low.length < 2) return true;
    const junk = [
      'login',
      'sign up',
      'register',
      'cookie',
      'privacy',
      'home',
      'next',
      'prev',
      'logo',
      'menu',
      'search',
      'javascript',
    ];
    for (final j in junk) {
      if (low == j) return true;
    }
    return false;
  }

  String? _extractTitle(String html) {
    final og = RegExp(
      r'<meta[^>]+property=["'']og:title["''][^>]+content=["'']([^"'']+)["'']',
      caseSensitive: false,
    ).firstMatch(html);
    if (og != null) return _cleanTitle(og.group(1)!);
    final t = RegExp(r'<title>([^<]+)</title>', caseSensitive: false)
        .firstMatch(html);
    if (t != null) {
      var s = _cleanTitle(t.group(1)!);
      s = s.split(RegExp(r'\s[-|–—]\s')).first.trim();
      if (s.length >= 2) return s;
    }
    return null;
  }

  String? _extractThumb(String html) {
    final og = RegExp(
      r'<meta[^>]+property=["'']og:image["''][^>]+content=["'']([^"'']+)["'']',
      caseSensitive: false,
    ).firstMatch(html);
    if (og != null) return og.group(1);
    return null;
  }

  List<StreamQuality> _extractStreams(String html, String base) {
    final streams = <StreamQuality>[];
    final seen = <String>{};

    void add(String? u, {int w = 0, int h = 0}) {
      if (u == null || u.isEmpty) return;
      var url = u.replaceAll(r'\/', '/').trim();
      if (url.startsWith('//')) url = 'https:$url';
      if (!url.startsWith('http')) url = _abs(base, url);
      if (!seen.add(url)) return;
      if (h <= 0) {
        final hm = RegExp(r'(\d{3,4})p').firstMatch(url);
        if (hm != null) h = int.tryParse(hm.group(1)!) ?? 0;
      }
      if (h <= 0) h = 720;
      if (w <= 0) w = (h * 16 / 9).round();
      streams.add(StreamQuality(width: w, height: h, url: url));
    }

    // HLS everywhere
    for (final m in RegExp(
      r'''["'](https?:\\?/\\?/[^"'\\s]+\.m3u8[^"'\\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1)?.replaceAll(r'\/', '/'), h: 720);
    }
    for (final m in RegExp(
      r'''["']([^"'\\s]+\.m3u8[^"'\\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1);
      if (u != null && !u.startsWith('data:')) add(u, h: 720);
    }

    // og:video
    final ogv = RegExp(
      r'<meta[^>]+property=["'']og:video(?::url)?["''][^>]+content=["'']([^"'']+)["'']',
      caseSensitive: false,
    ).firstMatch(html);
    if (ogv != null) add(ogv.group(1), h: 720);

    // <source src=
    for (final m in RegExp(
      r'''<source[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 480);
    }

    // video src=
    for (final m in RegExp(
      r'''<video[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 480);
    }

    // XVideos-style
    final hls = RegExp(r"setVideoHLS\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setVideoHLS\("([^"]+)"\)').firstMatch(html);
    if (hls != null) add(hls.group(1), h: 720);
    final high = RegExp(r"setVideoUrlHigh\('([^']+)'\)").firstMatch(html);
    if (high != null) add(high.group(1), h: 480);
    final low = RegExp(r"setVideoUrlLow\('([^']+)'\)").firstMatch(html);
    if (low != null) add(low.group(1), h: 240);

    // contentUrl JSON-LD
    for (final m in RegExp(
      r'"contentUrl"\s*:\s*"([^"]+)"',
    ).allMatches(html)) {
      add(m.group(1), h: 720);
    }

    // common file: "file":"http...
    for (final m in RegExp(
      r'''["']file["']\s*:\s*["'](https?[^"']+)["']''',
    ).allMatches(html)) {
      add(m.group(1), h: 720);
    }
    for (final m in RegExp(
      r'''["']src["']\s*:\s*["'](https?[^"']+\.(?:mp4|m3u8)[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 720);
    }

    // quality labeled
    for (final m in RegExp(
      r'''["'](\d{3,4})p?["']\s*:\s*["'](https?[^"']+)["']''',
    ).allMatches(html)) {
      final h = int.tryParse(m.group(1)!) ?? 0;
      add(m.group(2), h: h > 0 ? h : 720);
    }

    return streams;
  }
}
