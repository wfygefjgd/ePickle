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
        // Live API JSON
        if (site.kind == SiteKind.live &&
            (html.trimLeft().startsWith('{') ||
                html.trimLeft().startsWith('['))) {
          results.addAll(_parseLiveJson(html, base, seen, site));
        } else {
          results.addAll(_parseList(html, base, seen, site));
        }
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
      final path = Uri.tryParse(url)?.path ?? url;
      html = await _fetchWithMirrors(site, (b) => '$b$path');
    }

    // Live rooms: try HLS from room page / API snippets
    if (site.kind == SiteKind.live) {
      final live = await _extractLiveStreams(site, url, html, base);
      if (live.isNotEmpty) {
        return VideoDetail(
          url: url,
          title: _extractTitle(html) ?? site.name,
          durationSec: 0,
          thumb: _extractThumb(html),
          streams: live,
        );
      }
    }

    final title = _extractTitle(html) ?? url;
    final thumb = _extractThumb(html);
    var streams = _extractStreams(html, base);

    // MissAV / Jable often put m3u8 in packed JS or data-src
    if (streams.isEmpty) {
      streams = _extractStreamsLoose(html, base);
    }
    // Follow embed iframe once
    if (streams.isEmpty) {
      final emb = RegExp(
        r'''<iframe[^>]+src=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (emb != null) {
        try {
          final embUrl = _abs(base, emb.group(1)!);
          final embHtml = await _getHtml(
            embUrl,
            headers: {
              ...AppHttpHeaders.browser,
              'Referer': url,
            },
          );
          streams = _extractStreams(embHtml, _originOf(embUrl) ?? base);
          if (streams.isEmpty) {
            streams = _extractStreamsLoose(embHtml, _originOf(embUrl) ?? base);
          }
        } catch (_) {}
      }
    }

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
      case 'jable':
        return [
          if (tagId == 'new') (b) => '$b/latest-updates/',
          if (tagId == 'asian') (b) => '$b/categories/chinese-subtitle/',
          if (tagId == 'best') (b) => '$b/categories/hot/',
          (b) => '$b/latest-updates/',
          (b) => '$b/hot/',
          (b) => '$b/',
          (b) => '$b/categories/uncensored-leak/',
          (b) => '$b/categories/chinese-subtitle/',
        ];
      case 'missav':
        return [
          if (tagId == 'new') (b) => '$b/dm22/new',
          if (tagId == 'asian') (b) => '$b/dm247/cn',
          if (tagId == 'best') (b) => '$b/dm13/release',
          (b) => '$b/dm22/new',
          (b) => '$b/dm247/cn',
          (b) => '$b/dm13/release',
          (b) => '$b/en',
          (b) => '$b/',
        ];
      case 'javgg':
        return [
          (b) => '$b/',
          (b) => '$b/new-post/',
          (b) => '$b/genre/uncensored/',
          (b) => '$b/trending/',
          (b) => '$b/jav/',
        ];
      case 'javmix':
        return [
          (b) => '$b/',
          (b) => '$b/genre/uncensored',
          (b) => '$b/new',
        ];
      case 'av01':
        return [
          (b) => '$b/jp',
          (b) => '$b/jp/',
          (b) => '$b/',
          (b) => '$b/jp/latest',
          (b) => '$b/zh',
        ];
      case '7mmtv':
        return [
          (b) => '$b/zh',
          (b) => '$b/zh/',
          (b) => '$b/en',
          (b) => '$b/',
          (b) => '$b/zh/censored_list/all/1.html',
          (b) => '$b/zh/uncensored_list/all/1.html',
        ];
      case 'bestjavporn':
        return [
          (b) => '$b/zh/',
          (b) => '$b/',
          (b) => '$b/zh/new/',
          (b) => '$b/new/',
          (b) => '$b/zh/best/',
        ];
      case 'our55':
        return [
          (b) => '$b/',
          (b) => '$b/home.html',
          (b) => '$b/index.html',
          (b) => '$b/index.php',
          (b) => '$b/vod/show/id/1.html',
          (b) => '$b/index.php/vod/type/id/1.html',
          (b) => '$b/vodtype/1.html',
        ];
      case 'xqq88':
        return [
          (b) => '$b/home.html',
          (b) => '$b/',
          (b) => '$b/index.html',
          (b) => '$b/index.php',
          (b) => '$b/index.php/vod/type/id/1.html',
          (b) => '$b/vod/type/id/1.html',
          (b) => '$b/label/new.html',
        ];
      case 'redtube':
        return [
          if (tagId == 'new') (b) => '$b/?page=1',
          if (tagId == 'asian') (b) => '$b/redtube/asian',
          (b) => '$b/',
          (b) => '$b/?id=hottest',
          (b) => '$b/pornstar',
        ];
      case 'youporn':
        return [
          (b) => '$b/',
          (b) => '$b/?page=1',
          (b) => '$b/popular/',
          (b) => '$b/category/asian/',
          (b) => '$b/browse/time/',
        ];
      case 'spankbang':
        return [
          (b) => '$b/',
          (b) => '$b/trending_videos/',
          (b) => '$b/new_videos/',
          (b) => '$b/s/asian/',
          (b) => '$b/upcoming/',
        ];
      case 'freeporn':
        return [
          (b) => '$b/',
          (b) => '$b/videos',
          (b) => '$b/videos/',
          (b) => '$b/categories',
        ];
      case 'tnaflix':
        return [
          (b) => '$b/',
          (b) => '$b/new',
          (b) => '$b/popular',
          (b) => '$b/videos',
          (b) => '$b/categories',
        ];
      case 'stripchat':
        return [
          (b) => '$b/',
          (b) => '$b/female-cams',
          (b) => '$b/girls',
          (b) => '$b/tags/asian',
          (b) => '$b/api/models?limit=60&primaryTag=girls',
          (b) => '$b/api/front/models?limit=60&primaryTag=girls',
        ];
      case 'chaturbate':
        return [
          (b) => '$b/',
          (b) => '$b/female-cams/',
          (b) => '$b/asian-cams/',
          (b) => '$b/api/ts/roomlist/room-list/?limit=90',
          (b) => '$b/?page=1',
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

  List<VideoItem> _parseLiveJson(
    String raw,
    String base,
    Set<String> seen,
    SiteDef site,
  ) {
    final out = <VideoItem>[];
    // Chaturbate room list / stripchat models: extract username-like fields
    final nameRe = RegExp(
      r'''"(?:username|user__username|slug|login|room|modelName)"\s*:\s*"([a-zA-Z0-9_]{3,40})"''',
    );
    for (final m in nameRe.allMatches(raw)) {
      final name = m.group(1)!;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      final url = '$base/$name';
      // try nearby image
      String? thumb;
      final around = raw.substring(
        m.start > 200 ? m.start - 200 : 0,
        m.end + 300 < raw.length ? m.end + 300 : raw.length,
      );
      final im = RegExp(
        r'''https?:\\?/\\?/[^"'\s]+(?:jpg|jpeg|png|webp)''',
        caseSensitive: false,
      ).firstMatch(around);
      if (im != null) {
        thumb = im.group(0)!.replaceAll(r'\/', '/');
      }
      out.add(VideoItem(url: url, title: name, duration: 'LIVE', thumb: thumb));
      if (out.length >= 80) break;
    }
    return out;
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
        h.contains('/page/') ||
        h.endsWith('.css') ||
        h.endsWith('.js') ||
        h.endsWith('.xml') ||
        h.endsWith('.jpg') ||
        h.endsWith('.png')) {
      return false;
    }

    // Site-specific positive rules
    switch (site.id) {
      case 'jable':
        return RegExp(r'/videos?/[^/]+/?').hasMatch(h) ||
            RegExp(r'/[a-z0-9]+-[a-z0-9-]+/?$').hasMatch(h);
      case 'missav':
        return RegExp(r'/[a-z]{2,12}-?\d{2,5}').hasMatch(h) ||
            RegExp(r'/(dm\d+/)?[a-z0-9-]+/?$').hasMatch(h) &&
                !h.contains('/dm') &&
                h.split('/').where((e) => e.isNotEmpty).length >= 1;
      case 'javgg':
      case 'javmix':
      case 'bestjavporn':
        return RegExp(r'/(jav|video|movie|watch)/').hasMatch(h) ||
            RegExp(r'/[a-z]{2,10}-?\d{2,5}').hasMatch(h);
      case '7mmtv':
        return h.contains('/content/') ||
            h.contains('/cnplay/') ||
            h.contains('/enplay/') ||
            RegExp(r'_\d+\.html').hasMatch(h);
      case 'av01':
        return h.contains('/v/') || h.contains('/video/');
      case 'spankbang':
        return RegExp(r'/[a-z0-9-]+/video/').hasMatch(h) ||
            RegExp(r'/\d+/video/').hasMatch(h);
      case 'youporn':
      case 'redtube':
        return RegExp(r'/watch/').hasMatch(h) ||
            RegExp(r'/video\?id=').hasMatch(h) ||
            RegExp(r'/\d{5,}').hasMatch(h);
      case 'tnaflix':
        return h.contains('/video') || RegExp(r'/[^/]+/\d+').hasMatch(h);
      case 'eporner':
        return h.contains('/video-') || h.contains('/hd-porn/');
      case 'xhamster':
        return h.contains('/videos/') || RegExp(r'/movies/\d+').hasMatch(h);
      case 'xnxx':
        return RegExp(r'/video-[a-z0-9]+/').hasMatch(h);
      case 'our55':
      case 'xqq88':
        return h.contains('/vod/') ||
            h.contains('/play/') ||
            h.contains('/detail/') ||
            RegExp(r'/index\.php/vod/').hasMatch(h);
      case 'stripchat':
      case 'chaturbate':
        // room username path
        final parts = h.split('/').where((e) => e.isNotEmpty).toList();
        if (parts.length == 1 &&
            RegExp(r'^[a-zA-Z0-9_]{3,40}$').hasMatch(parts.first)) {
          return true;
        }
        if (h.contains('/in/?') || h.contains('join')) return false;
        return parts.isNotEmpty &&
            !['female-cams', 'male-cams', 'couples', 'tags', 'accounts', 'auth']
                .contains(parts.first);
    }

    // Generic positive patterns
    if (RegExp(r'/video[s./]').hasMatch(h)) return true;
    if (RegExp(r'/v/\d').hasMatch(h)) return true;
    if (RegExp(r'/watch').hasMatch(h)) return true;
    if (RegExp(r'/view_video').hasMatch(h)) return true;
    if (RegExp(r'/embed/').hasMatch(h)) return true;
    if (RegExp(r'/(movies?|clips?)/').hasMatch(h)) return true;
    if (RegExp(r'/\d{4,}/').hasMatch(h) && h.split('/').length >= 3) {
      return true;
    }
    if (RegExp(r'/[a-z]{2,10}-\d{2,5}').hasMatch(h)) return true;
    if (RegExp(r'/(uncensored|censored)/').hasMatch(h)) return true;
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
      var url = u
          .replaceAll(r'\/', '/')
          .replaceAll(r'\u002F', '/')
          .replaceAll('&amp;', '&')
          .trim();
      if (url.startsWith('//')) url = 'https:$url';
      if (!url.startsWith('http')) url = _abs(base, url);
      // Skip obvious non-media
      final low = url.toLowerCase();
      if (low.contains('.js') ||
          low.contains('.css') ||
          low.contains('favicon') ||
          low.endsWith('.jpg') ||
          low.endsWith('.png') ||
          low.endsWith('.webp')) {
        return;
      }
      if (!seen.add(url)) return;
      if (h <= 0) {
        final hm = RegExp(r'(\d{3,4})p').firstMatch(url);
        if (hm != null) h = int.tryParse(hm.group(1)!) ?? 0;
      }
      if (h <= 0) {
        if (low.contains('.m3u8')) {
          h = 720;
        } else if (low.contains('.mp4')) {
          h = 480;
        } else {
          h = 720;
        }
      }
      if (w <= 0) w = (h * 16 / 9).round();
      streams.add(StreamQuality(width: w, height: h, url: url));
    }

    // HLS absolute
    for (final m in RegExp(
      r'''["'](https?:\\?/\\?/[^"'\\s]+\.m3u8[^"'\\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1)?.replaceAll(r'\/', '/'), h: 720);
    }
    // HLS relative / escaped
    for (final m in RegExp(
      r'''["']([^"'\\s]+\.m3u8[^"'\\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1);
      if (u != null && !u.startsWith('data:')) add(u, h: 720);
    }
    // m3u8 without quotes nearby (packed)
    for (final m in RegExp(
      r'(https?:\\?/\\?/[^\s"''<>]+\.m3u8[^\s"''<>]*)',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1)?.replaceAll(r'\/', '/'), h: 720);
    }

    // mp4
    for (final m in RegExp(
      r'''["'](https?:[^"']+\.mp4[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 480);
    }

    // og:video
    final ogv = RegExp(
      r'<meta[^>]+property=["'']og:video(?::url)?["''][^>]+content=["'']([^"'']+)["'']',
      caseSensitive: false,
    ).firstMatch(html);
    if (ogv != null) add(ogv.group(1), h: 720);

    for (final m in RegExp(
      r'''<source[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 480);
    }
    for (final m in RegExp(
      r'''<video[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 480);
    }

    // XVideos-style helpers
    final hls = RegExp(r"setVideoHLS\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setVideoHLS\("([^"]+)"\)').firstMatch(html);
    if (hls != null) add(hls.group(1), h: 720);
    final high = RegExp(r"setVideoUrlHigh\('([^']+)'\)").firstMatch(html);
    if (high != null) add(high.group(1), h: 480);
    final low = RegExp(r"setVideoUrlLow\('([^']+)'\)").firstMatch(html);
    if (low != null) add(low.group(1), h: 240);

    // JSON-LD / common keys
    for (final m in RegExp(r'"contentUrl"\s*:\s*"([^"]+)"').allMatches(html)) {
      add(m.group(1), h: 720);
    }
    for (final m in RegExp(
      r'''["'](?:file|source|src|videoUrl|video_url|stream|hls|hlsUrl|m3u8)["']\s*:\s*["'](https?[^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1), h: 720);
    }
    for (final m in RegExp(
      r'''["'](\d{3,4})p?["']\s*:\s*["'](https?[^"']+)["']''',
    ).allMatches(html)) {
      final hh = int.tryParse(m.group(1)!) ?? 0;
      add(m.group(2), h: hh > 0 ? hh : 720);
    }

    // MacCMS / Chinese portals: player_aaaa / player_data
    final player = RegExp(
      r'player_aaaa\s*=\s*(\{.+?\})\s*;',
      dotAll: true,
    ).firstMatch(html);
    if (player != null) {
      final blob = player.group(1)!;
      final um = RegExp(r'''["']url["']\s*:\s*["']([^"']+)["']''').firstMatch(blob);
      if (um != null) add(um.group(1), h: 720);
    }
    final urlM = RegExp(
      r'''["']url["']\s*:\s*["'](https?[^"']+\.(?:m3u8|mp4)[^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (urlM != null) add(urlM.group(1), h: 720);

    return streams;
  }

  /// Broader second-pass for packed / unicode-escaped media URLs.
  List<StreamQuality> _extractStreamsLoose(String html, String base) {
    final decoded = html
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\x2F', '/');
    return _extractStreams(decoded, base);
  }

  Future<List<StreamQuality>> _extractLiveStreams(
    SiteDef site,
    String pageUrl,
    String html,
    String base,
  ) async {
    final streams = <StreamQuality>[];
    streams.addAll(_extractStreams(html, base));
    streams.addAll(_extractStreamsLoose(html, base));

    // Chaturbate: edge HLS often in initial data
    if (site.id == 'chaturbate') {
      final edge = RegExp(
        r'''https?:\\?/\\?/[^\s"'<>]*playlist\.m3u8[^\s"'<>]*''',
        caseSensitive: false,
      ).firstMatch(html);
      if (edge != null) {
        var u = edge.group(0)!.replaceAll(r'\/', '/');
        streams.add(StreamQuality(width: 1280, height: 720, url: u));
      }
      final hlsSrc = RegExp(
        r'''hls_source["']?\s*[:=]\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (hlsSrc != null) {
        var u = hlsSrc.group(1)!.replaceAll(r'\/', '/');
        if (u.startsWith('//')) u = 'https:$u';
        streams.add(StreamQuality(width: 1280, height: 720, url: u));
      }
    }

    // Stripchat: look for stream name / m3u8
    if (site.id == 'stripchat') {
      for (final m in RegExp(
        r'''https?:\\?/\\?/[^\s"'<>]*\.m3u8[^\s"'<>]*''',
        caseSensitive: false,
      ).allMatches(html)) {
        final u = m.group(0)!.replaceAll(r'\/', '/');
        streams.add(StreamQuality(width: 1280, height: 720, url: u));
      }
    }

    // Dedup
    final seen = <String>{};
    final out = <StreamQuality>[];
    for (final s in streams) {
      if (seen.add(s.url)) out.add(s);
    }
    return out;
  }
}
