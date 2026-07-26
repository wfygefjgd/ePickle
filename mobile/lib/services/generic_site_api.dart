import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import '../utils/des_ecb.dart';
import '../utils/http_client.dart';
import '../utils/http_headers.dart';
import 'phub_api.dart';
import 'source_catalog.dart';

/// Generic HTML scraper with mirror failover for tube / JAV-style sites.
class GenericSiteApi {
  static const _requestTimeout = Duration(seconds: 7);
  static const _feedResolveTimeout = Duration(seconds: 16);
  static const _searchResolveTimeout = Duration(seconds: 14);
  static const _detailResolveTimeout = Duration(seconds: 20);

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

  /// Minimal per-origin cookie store for age gates and session redirects.
  final Map<String, Map<String, String>> _cookies = {};

  Duration _requestBudget(DateTime? deadline) {
    if (deadline == null) return _requestTimeout;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.inMilliseconds <= 0) {
      throw TimeoutException('站点解析超时');
    }
    return remaining < _requestTimeout ? remaining : _requestTimeout;
  }

  Future<String> _getHtml(
    String url, {
    Map<String, String>? headers,
    Duration timeout = _requestTimeout,
  }) async {
    final origin = _originOf(url);
    final cookieHeader = origin == null ? null : _cookieHeader(origin);
    final res = await _dio
        .get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              ...AppHttpHeaders.forSite(origin ?? url),
              if (cookieHeader != null) 'Cookie': cookieHeader,
              if (headers != null) ...headers,
            },
            followRedirects: true,
            validateStatus: (s) => s != null && s < 500,
          ),
        )
        .timeout(timeout);
    _storeCookies(origin, res.headers);
    final status = res.statusCode ?? 0;
    if (res.statusCode == 403) {
      throw PhubException('访问被拒绝 (403)');
    }
    if (res.statusCode == 404) {
      throw PhubException('页面不存在 (404)');
    }
    if (status < 200 || status >= 400) {
      throw PhubException('站点返回异常状态 ($status)');
    }
    if (res.data == null || res.data!.isEmpty) {
      throw PhubException('空响应');
    }
    return res.data!;
  }

  String? _cookieHeader(String origin) {
    final values = _cookies[origin];
    if (values == null || values.isEmpty) return null;
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _storeCookies(String? origin, Headers headers) {
    if (origin == null) return;
    final raw = headers.map['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final jar = _cookies.putIfAbsent(origin, () => <String, String>{});
    for (final value in raw) {
      final pair = value.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final cookieValue = pair.substring(eq + 1).trim();
      if (cookieValue.isEmpty) {
        jar.remove(name);
      } else {
        jar[name] = cookieValue;
      }
    }
  }

  bool _isBlockedHtml(String html) {
    final low = html.toLowerCase();
    final trim = html.trimLeft();
    if (trim.startsWith('{') || trim.startsWith('[')) return false;
    if (html.length < 350) return true;
    if (low.contains('just a moment') && low.contains('cloudflare'))
      return true;
    if (low.contains('cf-browser-verification')) return true;
    if (low.contains('attention required') && low.contains('cloudflare')) {
      return true;
    }
    if (low.contains('服务暂不可用') || low.contains('正在跳转到发布页')) {
      return true;
    }
    // Age-gate only landing with no video cards
    if (low.contains('已满18') &&
        html.length < 8000 &&
        !low.contains('vod') &&
        !RegExp(r'/video').hasMatch(low)) {
      return true;
    }
    return false;
  }

  List<String> _mirrorsFor(SiteDef site) {
    if (site.mirrors.isNotEmpty) return List<String>.from(site.mirrors);
    return [site.primaryHost];
  }

  String _abs(String base, String path) {
    final p = path.trim();
    if (p.isEmpty) return base;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('//')) return 'https:$p';
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme) return p;
    return baseUri.resolve(p).toString();
  }

  Future<String> _fetchWithMirrors(
    SiteDef site,
    String Function(String base) pathBuilder, {
    Map<String, String>? extraHeaders,
    DateTime? deadline,
  }) async {
    final page = await _fetchPageWithMirrors(
      site,
      pathBuilder,
      extraHeaders: extraHeaders,
      deadline: deadline,
    );
    return page.html;
  }

  Future<_FetchedPage> _fetchPageWithMirrors(
    SiteDef site,
    String Function(String base) pathBuilder, {
    Map<String, String>? extraHeaders,
    bool Function(String html, String base)? accept,
    DateTime? deadline,
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
          if (extraHeaders != null) ...extraHeaders,
        };
        final html = await _getHtml(
          url,
          headers: headers,
          timeout: _requestBudget(deadline),
        );
        if (_isBlockedHtml(html)) {
          lastErr = PhubException('页面被拦截或无效');
          continue;
        }
        if (accept != null && !accept(html, base)) {
          lastErr = PhubException('${site.name} 页面结构不匹配');
          continue;
        }
        _mirrorIndex[site.id] = i;
        return _FetchedPage(html: html, url: url, base: base);
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
    int page = 1,
    int limit = 40,
    Set<String>? exclude,
  }) async {
    final deadline = DateTime.now().add(_feedResolveTimeout);
    final seen = <String>{...?exclude};
    final results = <VideoItem>[];
    final safePage = page < 1 ? 1 : page;

    // Site-specific API first (more reliable than HTML scrape).
    try {
      final api = await _fetchViaApi(
        site,
        tagId: tagId,
        page: safePage,
        limit: limit,
        seen: seen,
        deadline: deadline,
      );
      results.addAll(api);
    } catch (_) {}

    if (results.length < limit) {
      final paths = _listPaths(site, tagId, safePage);
      for (final pathFn in paths) {
        if (results.length >= limit) break;
        try {
          final fetched = await _fetchPageWithMirrors(
            site,
            pathFn,
            deadline: deadline,
            accept: (html, base) => _parseFeedResponse(
                    html,
                    base,
                    <String>{
                      ...seen,
                    },
                    site)
                .isNotEmpty,
          );
          results.addAll(
            _parseFeedResponse(fetched.html, fetched.base, seen, site),
          );
        } catch (_) {
          continue;
        }
      }
    }

    if (results.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw PhubException('${site.name} 列表解析超时，请重试或切换网络');
      }
      throw PhubException('无法从 ${site.name} 获取列表。\n请确认网络/代理，或该站结构有变。');
    }
    if (results.length > limit) return results.sublist(0, limit);
    return results;
  }

  List<VideoItem> _parseFeedResponse(
    String body,
    String base,
    Set<String> seen,
    SiteDef site,
  ) {
    final trim = body.trimLeft();
    if (trim.startsWith('{') || trim.startsWith('[')) {
      return [
        if (site.kind == SiteKind.live)
          ..._parseLiveJson(body, base, seen, site),
        if (site.kind == SiteKind.video)
          ..._parseGenericJsonList(body, base, seen, site),
      ];
    }
    return _parseList(body, base, seen, site);
  }

  /// Prefer official/public JSON APIs when available.
  Future<List<VideoItem>> _fetchViaApi(
    SiteDef site, {
    required String tagId,
    required int page,
    required int limit,
    required Set<String> seen,
    required DateTime deadline,
  }) async {
    switch (site.id) {
      case 'eporner':
        return _fetchEpornerApi(
          site,
          tagId: tagId,
          page: page,
          limit: limit,
          seen: seen,
          deadline: deadline,
        );
      case 'chaturbate':
        return _fetchChaturbateApi(
          site,
          page: page,
          limit: limit,
          seen: seen,
          deadline: deadline,
        );
      case 'stripchat':
        return _fetchStripchatApi(
          site,
          page: page,
          limit: limit,
          seen: seen,
          deadline: deadline,
        );
      case 'xqq88':
        return const [];
      default:
        return const [];
    }
  }

  Future<List<VideoItem>> _fetchEpornerApi(
    SiteDef site, {
    required String tagId,
    required int page,
    required int limit,
    required Set<String> seen,
    required DateTime deadline,
  }) async {
    final q = switch (tagId) {
      'asian' => 'asian',
      'new' => 'new',
      'best' => 'best',
      _ => 'hot',
    };
    final order = tagId == 'new' ? 'latest' : 'top-weekly';
    final out = <VideoItem>[];
    for (final base in _mirrorsFor(site)) {
      final b = base.replaceAll(RegExp(r'/$'), '');
      final url = '$b/api/v2/video/search/?query=${Uri.encodeQueryComponent(q)}'
          '&per_page=${limit.clamp(1, 60)}&page=$page&thumbsize=big'
          '&order=$order&gay=0&lq=1&format=json';
      try {
        final raw = await _getHtml(
          url,
          headers: {
            ...AppHttpHeaders.forSite(b),
            'Accept': 'application/json,text/plain,*/*',
          },
          timeout: _requestBudget(deadline),
        );
        final videos = RegExp(
          r'"url"\s*:\s*"(https?:[^"]+eporner[^"]+)"',
          caseSensitive: false,
        ).allMatches(raw);
        final titles = RegExp(
          r'"title"\s*:\s*"([^"]+)"',
        ).allMatches(raw).toList();
        final thumbs = RegExp(
          r'"(?:default|medium|big)url"\s*:\s*"(https?:[^"]+)"',
        ).allMatches(raw).toList();
        var i = 0;
        for (final m in videos) {
          final u = m.group(1)!.replaceAll(r'\/', '/');
          if (!seen.add(u)) {
            i++;
            continue;
          }
          String title = 'Eporner';
          if (i < titles.length) {
            title = _cleanTitle(titles[i].group(1)!.replaceAll(r'\/', '/'));
          }
          String? thumb;
          if (i < thumbs.length) {
            thumb = thumbs[i].group(1)!.replaceAll(r'\/', '/');
          }
          out.add(VideoItem(url: u, title: title, duration: '-', thumb: thumb));
          i++;
          if (out.length >= limit) break;
        }
        if (out.isNotEmpty) {
          _mirrorIndex[site.id] = _mirrorsFor(site).indexOf(base).clamp(0, 99);
          return out;
        }
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  Future<List<VideoItem>> _fetchChaturbateApi(
    SiteDef site, {
    required int page,
    required int limit,
    required Set<String> seen,
    required DateTime deadline,
  }) async {
    final out = <VideoItem>[];
    final offset = (page - 1) * limit;
    final endpoints = <String Function(String)>[
      (b) =>
          '$b/api/ts/roomlist/room-list/?limit=${limit.clamp(20, 90)}&offset=$offset',
      (b) =>
          '$b/affiliates/api/onlinerooms/?format=json&limit=$limit&offset=$offset',
      (b) => '$b/api/get_slate/?room=&limit=$limit',
    ];
    for (final pathFn in endpoints) {
      try {
        final html = await _fetchWithMirrors(
          site,
          pathFn,
          deadline: deadline,
        );
        final base = _mirrorsFor(
          site,
        )[_mirrorIndex[site.id] ?? 0]
            .replaceAll(RegExp(r'/$'), '');
        out.addAll(_parseLiveJson(html, base, seen, site));
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }
    return out;
  }

  Future<List<VideoItem>> _fetchStripchatApi(
    SiteDef site, {
    required int page,
    required int limit,
    required Set<String> seen,
    required DateTime deadline,
  }) async {
    final out = <VideoItem>[];
    final offset = (page - 1) * limit;
    final endpoints = <String Function(String)>[
      (b) =>
          '$b/api/front/models?limit=${limit.clamp(20, 80)}&offset=$offset&primaryTag=girls&sortBy=stripRanking',
      (b) => '$b/api/models?limit=$limit&offset=$offset&primaryTag=girls',
      (b) =>
          '$b/api/front/v2/models?limit=$limit&offset=$offset&primaryTag=girls',
    ];
    for (final pathFn in endpoints) {
      try {
        final html = await _fetchWithMirrors(
          site,
          pathFn,
          deadline: deadline,
        );
        final base = _mirrorsFor(
          site,
        )[_mirrorIndex[site.id] ?? 0]
            .replaceAll(RegExp(r'/$'), '');
        out.addAll(_parseLiveJson(html, base, seen, site));
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }
    return out;
  }

  List<VideoItem> _parseGenericJsonList(
    String raw,
    String base,
    Set<String> seen,
    SiteDef site,
  ) {
    final out = <VideoItem>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return out;
    }

    String? firstString(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is Map) {
          final nested = Map<String, dynamic>.from(value);
          for (final nestedKey in const ['url', 'src', 'path']) {
            final nestedValue = nested[nestedKey];
            if (nestedValue is String && nestedValue.trim().isNotEmpty) {
              return nestedValue.trim();
            }
          }
        }
      }
      return null;
    }

    void visit(dynamic node) {
      if (out.length >= 80) return;
      if (node is List) {
        for (final child in node) {
          visit(child);
          if (out.length >= 80) break;
        }
        return;
      }
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node);
      var href = firstString(map, const [
        'path',
        'url',
        'link',
        'permalink',
        'videoUrl',
        'video_url',
      ]);
      final slug = firstString(map, const ['slug']);
      href ??= slug;
      if (href != null) {
        href = href.replaceAll(r'\/', '/');
        if (slug == href && !href.contains('/') && site.id == 'av01') {
          href = '/v/$href';
        }
        final title = firstString(map, const [
          'title',
          'name',
          'videoTitle',
          'video_title',
        ]);
        if (title != null &&
            title.length >= 2 &&
            !_isJunkTitle(title) &&
            _looksLikeVideoPath(href, site)) {
          final abs = _abs(base, href);
          final key = abs.split('#').first.split('?').first;
          if (seen.add(key)) {
            final thumb = firstString(map, const [
              'thumbnail',
              'thumb',
              'image',
              'poster',
              'cover',
            ]);
            final duration = firstString(map, const [
                  'duration',
                  'durationText',
                  'duration_text',
                ]) ??
                '-';
            out.add(
              VideoItem(
                url: abs,
                title: _cleanTitle(title),
                duration: duration,
                thumb: thumb == null ? null : _abs(base, thumb),
              ),
            );
          }
        }
      }
      for (final value in map.values) {
        if (value is Map || value is List) visit(value);
        if (out.length >= 80) break;
      }
    }

    visit(decoded);
    return out;
  }

  Future<List<VideoItem>> search(
    SiteDef site,
    String query, {
    int page = 1,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final deadline = DateTime.now().add(_searchResolveTimeout);
    final enc = Uri.encodeQueryComponent(q);
    final paths = _searchPaths(site, enc, page);
    final seen = <String>{};
    for (final pathFn in paths) {
      try {
        final fetched = await _fetchPageWithMirrors(
          site,
          pathFn,
          deadline: deadline,
          accept: (html, base) =>
              _parseSearchResponse(html, base, <String>{}, site).isNotEmpty,
        );
        final list = _parseSearchResponse(
          fetched.html,
          fetched.base,
          seen,
          site,
        );
        if (list.isNotEmpty) return list;
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) break;
        continue;
      }
    }
    return [];
  }

  List<VideoItem> _parseSearchResponse(
    String body,
    String base,
    Set<String> seen,
    SiteDef site,
  ) {
    final trim = body.trimLeft();
    if (trim.startsWith('{') || trim.startsWith('[')) {
      return _parseGenericJsonList(body, base, seen, site);
    }
    return _parseList(body, base, seen, site);
  }

  Future<VideoDetail> getVideoDetail(SiteDef site, String url) async {
    final parsed = Uri.tryParse(url);
    final suffix = parsed == null
        ? url
        : '${parsed.path}${parsed.hasQuery ? '?${parsed.query}' : ''}';
    final candidates = <({String url, String base, int? mirrorIndex})>[];
    final originalBase = _originOf(url);
    if (originalBase != null) {
      candidates.add((url: url, base: originalBase, mirrorIndex: null));
    }
    final mirrors = _mirrorsFor(site);
    final start = (_mirrorIndex[site.id] ?? 0).clamp(0, mirrors.length - 1);
    for (var n = 0; n < mirrors.length; n++) {
      final i = (start + n) % mirrors.length;
      final base = mirrors[i].replaceAll(RegExp(r'/$'), '');
      final candidateUrl = _abs(
        base,
        suffix.startsWith('/') ? suffix : '/$suffix',
      );
      if (candidates.any((e) => e.url == candidateUrl)) continue;
      candidates.add((url: candidateUrl, base: base, mirrorIndex: i));
    }

    Object? lastError;
    final deadline = DateTime.now().add(_detailResolveTimeout);
    for (final candidate in candidates) {
      try {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.inMilliseconds <= 0) break;
        final html = await _getHtml(
          candidate.url,
          headers: AppHttpHeaders.forSite(candidate.base),
          timeout: remaining < _requestTimeout ? remaining : _requestTimeout,
        );
        if (_isBlockedHtml(html)) {
          throw PhubException('页面被拦截或无效');
        }
        final parseBudget = deadline.difference(DateTime.now());
        if (parseBudget.inMilliseconds <= 0) break;
        final detail = await _parseVideoDetail(
          site,
          candidate.url,
          html,
          candidate.base,
        ).timeout(parseBudget);
        if (candidate.mirrorIndex != null) {
          _mirrorIndex[site.id] = candidate.mirrorIndex!;
        }
        return detail;
      } catch (e) {
        lastError = e;
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      throw PhubException('${site.name} 播放地址解析超时');
    }
    throw lastError ?? PhubException('无法解析播放地址：${site.name}');
  }

  Future<VideoDetail> _parseVideoDetail(
    SiteDef site,
    String url,
    String html,
    String base,
  ) async {
    // Live rooms: try HLS from room page / API snippets
    if (site.kind == SiteKind.live) {
      final live = await _extractLiveStreams(site, url, html, base);
      if (live.isNotEmpty) {
        return VideoDetail(
          url: url,
          title: _extractTitle(html) ?? _usernameFromUrl(url) ?? site.name,
          durationSec: 0,
          thumb: _resolvedThumb(html, url),
          streams: live,
        );
      }
      throw PhubException('无法获取直播流：${site.name}（主播可能离线）');
    }

    // Eporner: dedicated AJAX/download endpoints
    if (site.id == 'eporner') {
      final ep = await _extractEpornerStreams(url, html, base);
      if (ep.isNotEmpty) {
        return VideoDetail(
          url: url,
          title: _extractTitle(html) ?? url,
          durationSec: _extractDurationSec(html),
          thumb: _resolvedThumb(html, url),
          streams: ep,
        );
      }
    }

    // MindGeek family (YouPorn / RedTube): mediaDefinitions like Pornhub
    if (site.id == 'youporn' || site.id == 'redtube') {
      final mg = _extractMindGeekStreams(html);
      if (mg.isNotEmpty) {
        return VideoDetail(
          url: url,
          title: _extractTitle(html) ?? url,
          durationSec: _extractDurationSec(html),
          thumb: _resolvedThumb(html, url),
          streams: mg,
        );
      }
    }

    var title = _extractTitle(html) ?? url;
    // MissAV / JAV list pages often leak wrong og:title — prefer code in URL
    if (site.id == 'missav' ||
        site.id == 'javmix' ||
        site.id == 'javgg' ||
        site.id == 'jable' ||
        site.id == '7mmtv') {
      final code = _javCodeFromUrl(url);
      if (code != null) {
        final tLow = title.toLowerCase();
        if (!tLow.contains(code.toLowerCase()) ||
            title.length < 4 ||
            _isJunkTitle(title)) {
          title = code;
        }
      }
    }

    final thumb = _resolvedThumb(html, url);
    // Resolve site-specific player formats before broad URL matching. This
    // avoids mistaking hover previews and ad assets for the full video.
    var streams = <StreamQuality>[
      ..._extractEncryptedSiteStreams(html),
      ..._extractKvsStreams(html, url),
    ];
    if (streams.isEmpty) {
      streams = _extractStreams(html, url);
    }

    // MissAV / Jable often put m3u8 in packed JS or data-src
    if (streams.isEmpty) {
      streams = _extractStreamsLoose(html, url);
    }
    if (streams.isEmpty) {
      streams = await _resolveMacCmsPlayer(html, url, url);
    }
    // Follow embed iframe (up to 2 levels)
    if (streams.isEmpty) {
      streams = await _followEmbeds(html, url, url, depth: 2);
    }
    // SpankBang stream_url / stream_data
    if (streams.isEmpty && site.id == 'spankbang') {
      streams = _extractSpankbang(html, base);
    }
    // BestJAVPorn data-mediabook / encrypted player (best-effort)
    if (streams.isEmpty && site.id == 'bestjavporn') {
      streams = _extractBestJav(html, base);
    }

    streams = _filterPreviewStreams(streams);
    if (streams.isEmpty) {
      throw PhubException('无法解析播放地址：${site.name}');
    }
    streams.sort((a, b) {
      final ah = a.url.toLowerCase().contains('.m3u8') ? 1 : 0;
      final bh = b.url.toLowerCase().contains('.m3u8') ? 1 : 0;
      if (ah != bh) return bh.compareTo(ah);
      return b.pixels.compareTo(a.pixels);
    });
    return VideoDetail(
      url: url,
      title: title,
      durationSec: _extractDurationSec(html),
      thumb: thumb,
      streams: streams,
    );
  }

  String? _usernameFromUrl(String url) {
    final parts = Uri.tryParse(url)?.pathSegments ?? const [];
    for (final p in parts.reversed) {
      if (p.isEmpty) continue;
      if (RegExp(r'^[a-zA-Z0-9_]{3,40}$').hasMatch(p)) return p;
    }
    return null;
  }

  String? _javCodeFromUrl(String url) {
    final m = RegExp(r'([a-zA-Z]{2,12}-?\d{2,5}[a-zA-Z]?)').firstMatch(url);
    return m?.group(1)?.toUpperCase();
  }

  int _extractDurationSec(String html) {
    final iso = _metaContent(html, {'duration'});
    if (iso != null) {
      final match = RegExp(
        r'^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
        caseSensitive: false,
      ).firstMatch(iso);
      if (match != null) {
        final days = int.tryParse(match.group(1) ?? '') ?? 0;
        final hours = int.tryParse(match.group(2) ?? '') ?? 0;
        final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
        final total = days * 86400 + hours * 3600 + minutes * 60 + seconds;
        if (total > 0) return total;
      }
    }
    final meta = RegExp(
      r'<meta[^>]*(?:property|name)=["'
      '](?:video:)?duration["'
      '][^>]*content=["'
      '](\d+)["'
      ']',
      caseSensitive: false,
    ).firstMatch(html);
    if (meta != null) return int.tryParse(meta.group(1)!) ?? 0;
    final flash = RegExp(
      r'''["']video_duration["']\s*:\s*["']?(\d+)''',
    ).firstMatch(html);
    if (flash != null) return int.tryParse(flash.group(1)!) ?? 0;
    final seconds = RegExp(
      r'''["'](?:length_sec|duration_sec)["']\s*:\s*["']?(\d+)''',
      caseSensitive: false,
    ).firstMatch(html);
    if (seconds != null) return int.tryParse(seconds.group(1)!) ?? 0;
    final minutes = RegExp(
      r'''(?:class=["'][^"']*vid-length[^"']*["'][^>]*>|Duration:\s*)(\d+)\s*min''',
      caseSensitive: false,
    ).firstMatch(html);
    if (minutes != null) return (int.tryParse(minutes.group(1)!) ?? 0) * 60;
    return 0;
  }

  String? _macCmsPlayerBlob(String html) {
    for (final re in [
      RegExp(
        r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*;?\s*</script>',
        caseSensitive: false,
      ),
      RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*;', caseSensitive: false),
      RegExp(r'player_data\s*=\s*(\{[\s\S]*?\})\s*;', caseSensitive: false),
    ]) {
      final match = re.firstMatch(html);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _decodeMacCmsUrl(String value, int encrypt) {
    var decoded = value.replaceAll(r'\/', '/');
    try {
      if (encrypt == 2) decoded = utf8.decode(base64.decode(decoded));
      if (encrypt == 1 || encrypt == 2) decoded = Uri.decodeFull(decoded);
    } catch (_) {}
    return decoded;
  }

  bool _looksLikeMediaUrl(String url) {
    final low = url.toLowerCase();
    return low.contains('.m3u8') ||
        low.contains('.mp4') ||
        low.contains('.flv') ||
        low.contains('.webm');
  }

  Future<List<StreamQuality>> _resolveMacCmsPlayer(
    String html,
    String pageUrl,
    String base,
  ) async {
    final blob = _macCmsPlayerBlob(html);
    if (blob == null) return const [];
    final urlMatch = RegExp(
      r'''["']url["']\s*:\s*["']([^"']+)["']''',
    ).firstMatch(blob);
    if (urlMatch == null) return const [];
    final encrypt = int.tryParse(
          RegExp(
                r'''["']encrypt["']\s*:\s*["']?(\d+)''',
              ).firstMatch(blob)?.group(1) ??
              '',
        ) ??
        0;
    final playerUrl = _decodeMacCmsUrl(urlMatch.group(1)!, encrypt);
    if (_looksLikeMediaUrl(playerUrl)) {
      return _extractStreams('"file":"$playerUrl"', base);
    }

    final parse = RegExp(
      r'''["']parse["']\s*:\s*["']([^"']+)["']''',
    ).firstMatch(blob)?.group(1)?.replaceAll(r'\/', '/');
    String target;
    if (parse != null && parse.isNotEmpty) {
      final resolver = _abs(base, parse);
      final encoded = Uri.encodeQueryComponent(playerUrl);
      if (resolver.contains('{url}')) {
        target = resolver.replaceAll('{url}', encoded);
      } else if (resolver.endsWith('=') || resolver.endsWith('/')) {
        target = '$resolver$encoded';
      } else {
        target = '$resolver${resolver.contains('?') ? '&' : '?'}url=$encoded';
      }
    } else {
      target = _abs(base, playerUrl);
    }

    try {
      final resolvedHtml = await _getHtml(
        target,
        headers: {
          ...AppHttpHeaders.forSite(_originOf(target) ?? base),
          'Referer': pageUrl,
        },
      );
      var streams = _extractStreams(resolvedHtml, _originOf(target) ?? base);
      if (streams.isEmpty) {
        streams = _extractStreamsLoose(resolvedHtml, _originOf(target) ?? base);
      }
      if (streams.isEmpty) {
        streams = await _followEmbeds(
          resolvedHtml,
          target,
          target,
          depth: 1,
        );
      }
      return _filterPreviewStreams(streams);
    } catch (_) {
      return const [];
    }
  }

  Future<List<StreamQuality>> _followEmbeds(
    String html,
    String pageUrl,
    String base, {
    int depth = 1,
  }) async {
    if (depth <= 0) return const [];
    final re = RegExp(
      r'''<iframe[^>]+(?:src|data-src|data-lazy-src|data-embed)=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final emb in re.allMatches(html)) {
      try {
        final embUrl = _abs(pageUrl, emb.group(1)!);
        if (embUrl.contains('google') ||
            embUrl.contains('facebook') ||
            embUrl.contains('twitter')) {
          continue;
        }
        final embHtml = await _getHtml(
          embUrl,
          headers: {
            ...AppHttpHeaders.forSite(_originOf(embUrl) ?? base),
            'Referer': pageUrl,
          },
        );
        var streams = <StreamQuality>[
          ..._extractEncryptedSiteStreams(embHtml),
          ..._extractKvsStreams(embHtml, embUrl),
        ];
        if (streams.isEmpty) {
          streams = _extractStreams(embHtml, embUrl);
        }
        if (streams.isEmpty) {
          streams = _extractStreamsLoose(embHtml, embUrl);
        }
        if (streams.isEmpty) {
          streams = await _followEmbeds(
            embHtml,
            embUrl,
            embUrl,
            depth: depth - 1,
          );
        }
        streams = _filterPreviewStreams(streams);
        if (streams.isNotEmpty) return streams;
      } catch (_) {}
    }
    return const [];
  }

  Future<List<StreamQuality>> _extractEpornerStreams(
    String pageUrl,
    String html,
    String base,
  ) async {
    final out = <StreamQuality>[];
    // Direct in page
    out.addAll(_extractStreams(html, base));
    out.addAll(_extractStreamsLoose(html, base));

    // /xhr/video/ID or download hash links
    final idm = RegExp(r'/video-([A-Za-z0-9]+)/').firstMatch(pageUrl) ??
        RegExp(r'/video-([A-Za-z0-9]+)/').firstMatch(html);
    final vid = idm?.group(1);
    if (vid != null) {
      for (final path in [
        '/api/v2/video/id/?id=$vid&format=json',
        '/xhr/video/$vid/',
        '/download-video/$vid/',
      ]) {
        try {
          final raw = await _getHtml(
            '$base$path',
            headers: {
              ...AppHttpHeaders.forSite(base),
              'Referer': pageUrl,
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': 'application/json,text/plain,*/*',
            },
          );
          out.addAll(_extractStreams(raw, base));
          out.addAll(_extractStreamsLoose(raw, base));
          // eporner sources array
          for (final m in RegExp(
            r'''"(?:src|url)"\s*:\s*"(https?:[^"]+)"''',
          ).allMatches(raw)) {
            final u = m.group(1)!.replaceAll(r'\/', '/');
            if (u.contains('.mp4') || u.contains('.m3u8')) {
              out.add(StreamQuality(width: 1280, height: 720, url: u));
            }
          }
        } catch (_) {}
      }
    }
    return _filterPreviewStreams(out);
  }

  List<StreamQuality> _extractMindGeekStreams(String html) {
    final streams = <StreamQuality>[];
    final seen = <String>{};

    // mediaDefinitions JSON array (Pornhub / YouPorn / RedTube)
    final block = RegExp(
      r'''mediaDefinitions\s*[:=]\s*(\[[\s\S]*?\])\s*[,;}]''',
    ).firstMatch(html);
    final blob = block?.group(1) ?? html;

    for (final m in RegExp(
      r'''\{[^{}]*?"videoUrl"\s*:\s*"(https?:[^"]+)"[^{}]*?\}''',
      caseSensitive: false,
    ).allMatches(blob)) {
      final obj = m.group(0)!;
      var url = RegExp(
        r'''"videoUrl"\s*:\s*"(https?:[^"]+)"''',
      ).firstMatch(obj)?.group(1)?.replaceAll(r'\/', '/');
      if (url == null || url.isEmpty) continue;
      if (_isPreviewUrl(url)) continue;
      // Prefer full streams; HLS ordering is applied after all candidates parse.
      var height = int.tryParse(
            RegExp(r'''"height"\s*:\s*(\d+)''').firstMatch(obj)?.group(1) ?? '',
          ) ??
          0;
      if (height <= 0) {
        height = int.tryParse(
              RegExp(
                    r'''"quality"\s*:\s*"?(\d+)''',
                  ).firstMatch(obj)?.group(1) ??
                  '',
            ) ??
            0;
      }
      if (height <= 0) {
        height = url.contains('m3u8') ? 720 : 480;
      }
      if (!seen.add(url)) continue;
      final width = (height * 16 / 9).round();
      streams.add(StreamQuality(width: width, height: height, url: url));
    }

    // qualityItems (YouPorn)
    for (final m in RegExp(
      r'''"quality_(\d+p)"\s*:\s*"(https?:[^"]+)"''',
    ).allMatches(html)) {
      final url = m.group(2)!.replaceAll(r'\/', '/');
      if (_isPreviewUrl(url)) continue;
      if (!seen.add(url)) continue;
      final h = int.tryParse(m.group(1)!.replaceAll('p', '')) ?? 720;
      streams.add(
        StreamQuality(width: (h * 16 / 9).round(), height: h, url: url),
      );
    }

    return streams;
  }

  List<StreamQuality> _extractSpankbang(String html, String base) {
    final out = <StreamQuality>[];
    final streamData = RegExp(
      r'''stream_data\s*=\s*(\{[\s\S]*?\})\s*;''',
    ).firstMatch(html);
    final blob = streamData?.group(1) ?? html;
    for (final m in RegExp(
      r'''["'](\d+p)["']\s*:\s*\[\s*["'](https?[^"']+)["']''',
    ).allMatches(blob)) {
      final h = int.tryParse(m.group(1)!.replaceAll('p', '')) ?? 720;
      final u = m.group(2)!.replaceAll(r'\/', '/');
      if (!_isPreviewUrl(u)) {
        out.add(StreamQuality(width: (h * 16 / 9).round(), height: h, url: u));
      }
    }
    for (final key in [
      'm3u8',
      'stream_url_240p',
      'stream_url_320p',
      'stream_url_480p',
      'stream_url_720p',
      'stream_url_1080p',
    ]) {
      final m = RegExp(
        '''['"]$key['"]\\s*:\\s*['"](https?[^"']+)['"]''',
      ).firstMatch(html);
      if (m != null) {
        final u = m.group(1)!.replaceAll(r'\/', '/');
        if (!_isPreviewUrl(u)) {
          out.add(StreamQuality(width: 1280, height: 720, url: u));
        }
      }
    }
    out.addAll(_extractStreams(html, base));
    return _filterPreviewStreams(out);
  }

  /// Kernel Video Sharing player used by current JavMix/JavGG mirrors.
  List<StreamQuality> _extractKvsStreams(String html, String base) {
    final out = <StreamQuality>[];
    final seen = <String>{};
    for (final match in RegExp(
      r'''(?:video_url|event_reporting2|video_alt_url\d*)\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      var value = match.group(1)!.replaceAll(r'\/', '/').trim();
      final absoluteAt = value.indexOf('http');
      if (absoluteAt > 0 && value.startsWith('function/')) {
        value = value.substring(absoluteAt);
      }
      if (!value.startsWith('http')) value = _abs(base, value);
      final low = value.toLowerCase();
      if (!low.contains('/get_file/') &&
          !low.contains('.mp4') &&
          !low.contains('.m3u8')) {
        continue;
      }
      if (RegExp(r'''\.(?:jpe?g|png|webp|gif)(?:[?#]|$)''').hasMatch(low)) {
        continue;
      }
      if (_isPreviewUrl(value) || !seen.add(value)) continue;
      out.add(
        StreamQuality(
          width: 1280,
          height: low.contains('m3u8') ? 720 : 480,
          url: value,
        ),
      );
    }
    return out;
  }

  /// Our55/88XQQ family encrypts `label$hlsUrl` with DES-ECB-PKCS7. The key
  /// is the first eight UTF-8 bytes of the video id, matching CryptoJS DES.
  List<StreamQuality> _extractEncryptedSiteStreams(String html) {
    final config = RegExp(
      r'''video\s*:\s*\{[\s\S]{0,500}?id\s*:\s*["']([^"']+)["'][\s\S]{0,500}?data\s*:\s*\[([^\]]+)\]''',
      caseSensitive: false,
    ).firstMatch(html);
    if (config == null) return const [];
    final id = config.group(1)!;
    if (utf8.encode(id).length < 8) return const [];

    final out = <StreamQuality>[];
    final seen = <String>{};
    for (final encodedMatch in RegExp(
      r'''["']([A-Za-z0-9+/]{24,}={0,2})["']''',
    ).allMatches(config.group(2)!)) {
      try {
        final clear = DesEcbPkcs7.decryptBase64Utf8(
          encodedMatch.group(1)!,
          id,
        );
        final url = clear.split(r'$').map((part) => part.trim()).firstWhere(
              (part) => part.startsWith('http') && part.contains('.m3u8'),
              orElse: () => '',
            );
        if (url.isEmpty || !seen.add(url)) continue;
        out.add(StreamQuality(width: 1280, height: 720, url: url));
      } catch (_) {}
    }
    return out;
  }

  List<StreamQuality> _extractBestJav(String html, String base) {
    final out = <StreamQuality>[];
    // Hover previews are short — skip data-mediabook unless nothing else
    for (final m in RegExp(
      r'''["'](https?://[^"']+\.(?:m3u8|mp4)[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1)!;
      if (_isPreviewUrl(u)) continue;
      out.add(
        StreamQuality(
          width: 1280,
          height: u.contains('m3u8') ? 720 : 480,
          url: u,
        ),
      );
    }
    // source tags
    out.addAll(_extractStreams(html, base));
    if (out.isEmpty) {
      // last resort: mediabook previews (may be short)
      for (final m in RegExp(
        r'''data-mediabook=["'](https?://[^"']+)["']''',
        caseSensitive: false,
      ).allMatches(html)) {
        out.add(StreamQuality(width: 640, height: 360, url: m.group(1)!));
      }
    }
    return _filterPreviewStreams(out);
  }

  bool _isPreviewUrl(String url) {
    final low = url.toLowerCase();
    if (low.contains('trailer')) return true;
    if (low.contains('preview')) return true;
    if (low.contains('thumb')) return true;
    if (low.contains('sample') && !low.contains('m3u8')) return true;
    if (low.contains('mediabook')) return true;
    if (low.contains('static.eporner.com/na.mp4')) return true;
    if (RegExp(r'''/(?:na|unavailable|not[-_]?found)\.mp4(?:[?#/]|$)''')
        .hasMatch(low)) {
      return true;
    }
    if (low.contains('/preview.')) return true;
    // MindGeek 9s teaser segments often under get_media with very short tokens
    if (RegExp(r'[_-](9|10|15)s[_.-]').hasMatch(low)) return true;
    return false;
  }

  List<StreamQuality> _filterPreviewStreams(List<StreamQuality> input) {
    final seen = <String>{};
    final full = <StreamQuality>[];
    for (final s in input) {
      if (s.url.isEmpty || !seen.add(s.url)) continue;
      if (!_isPreviewUrl(s.url)) full.add(s);
    }
    return full;
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

  List<String Function(String base)> _listPaths(
    SiteDef site,
    String tagId,
    int page,
  ) {
    final id = site.id;
    final p = page < 1 ? 1 : page;
    // Site-specific first paths
    switch (id) {
      case 'xnxx':
        return [
          if (tagId == 'new') (b) => '$b/search/new/$p',
          if (tagId == 'asian') (b) => '$b/?k=asian&p=$p',
          if (tagId == 'best') (b) => '$b/best/$p',
          if (tagId == 'hot') (b) => '$b/hits/$p',
          (b) => '$b/search/hot/$p',
        ];
      case 'xhamster':
        return [
          if (tagId == 'new') (b) => '$b/newest/$p',
          if (tagId == 'asian') (b) => '$b/categories/asian/$p',
          if (tagId == 'best') (b) => '$b/best/$p',
          if (tagId == 'hot') (b) => '$b/hottest/$p',
          (b) => '$b/?page=$p',
        ];
      case 'eporner':
        return [
          if (tagId == 'new') (b) => '$b/recent/$p/',
          if (tagId == 'asian') (b) => '$b/cat/asian/$p/',
          if (tagId == 'best') (b) => '$b/top-rated/$p/',
          if (tagId == 'hot') (b) => '$b/best-videos/$p/',
        ];
      case 'jable':
        return [
          if (tagId == 'new') (b) => '$b/latest-updates/$p/',
          if (tagId == 'asian') (b) => '$b/categories/chinese-subtitle/$p/',
          if (tagId == 'best') (b) => '$b/hot/$p/',
          if (tagId == 'hot') (b) => '$b/categories/hot/$p/',
          (b) => '$b/latest-updates/$p/',
        ];
      case 'missav':
        return [
          if (tagId == 'new') (b) => '$b/dm22/new?page=$p',
          if (tagId == 'asian') (b) => '$b/dm247/cn?page=$p',
          if (tagId == 'best') (b) => '$b/dm13/release?page=$p',
          if (tagId == 'hot') (b) => '$b/en?page=$p',
          (b) => '$b/dm22/new?page=$p',
        ];
      case 'javgg':
        return [
          if (p == 1) (b) => '$b/',
          if (tagId == 'new') (b) => '$b/new-post/page/$p/',
          if (tagId == 'asian') (b) => '$b/genre/censored/page/$p/',
          if (tagId == 'best') (b) => '$b/trending/page/$p/',
          if (tagId == 'hot') (b) => '$b/jav/page/$p/',
          (b) => '$b/page/$p/',
        ];
      case 'javmix':
        return [
          if (p == 1) (b) => '$b/',
          if (tagId == 'new') (b) => '$b/new/page/$p',
          if (tagId == 'asian') (b) => '$b/genre/censored/page/$p',
          if (tagId == 'best') (b) => '$b/popular/page/$p',
          if (tagId == 'hot') (b) => '$b/genre/uncensored/page/$p',
          (b) => '$b/page/$p',
        ];
      case '7mmtv':
        return [
          if (tagId == 'new') (b) => '$b/zh/new_list/all/$p.html',
          if (tagId == 'asian') (b) => '$b/zh/censored_list/all/$p.html',
          if (tagId == 'best') (b) => '$b/zh/top_list/all/$p.html',
          if (tagId == 'hot') (b) => '$b/zh/uncensored_list/all/$p.html',
          (b) => '$b/zh?page=$p',
        ];
      case 'bestjavporn':
        return [
          if (p == 1) (b) => '$b/',
          if (tagId == 'new') (b) => '$b/zh/new/page/$p/',
          if (tagId == 'asian') (b) => '$b/zh/censored/page/$p/',
          if (tagId == 'best') (b) => '$b/zh/best/page/$p/',
          if (tagId == 'hot') (b) => '$b/zh/page/$p/',
          (b) => '$b/page/$p/',
        ];
      case 'our55':
        return [
          if (p == 1) (b) => '$b/',
          if (tagId == 'new') (b) => '$b/index.php/vod/show/page/$p.html',
          if (tagId == 'asian') (b) => '$b/chinese/page/$p/',
          if (tagId == 'best')
            (b) => '$b/index.php/vod/show/by/hits/page/$p.html',
          if (tagId == 'hot') (b) => '$b/nocode/page/$p/',
          (b) => '$b/index.php/vod/type/id/1/page/$p.html',
        ];
      case 'xqq88':
        return [
          if (p == 1) (b) => '$b/',
          if (tagId == 'new') (b) => '$b/label/new/page/$p.html',
          if (tagId == 'asian') (b) => '$b/chinese/page/$p/',
          if (tagId == 'best')
            (b) => '$b/index.php/vod/show/by/hits/page/$p.html',
          if (tagId == 'hot') (b) => '$b/index.php/vod/type/id/1/page/$p.html',
          (b) => '$b/home.html?page=$p',
        ];
      case 'av01':
        return [
          if (tagId == 'new')
            (b) => '$b/api/v1/videos?page=$p&limit=40&sort=new',
          if (tagId == 'asian')
            (b) => '$b/api/v1/videos?page=$p&limit=40&category=jp',
          if (tagId == 'best')
            (b) => '$b/api/v1/videos?page=$p&limit=40&sort=rating',
          if (tagId == 'hot')
            (b) => '$b/api/v1/videos?page=$p&limit=40&sort=hot',
          (b) => '$b/api/videos?page=$p&limit=40',
          (b) => '$b/jp?page=$p',
        ];
      case 'redtube':
        return [
          if (tagId == 'new') (b) => '$b/?page=$p&ordering=newest',
          if (tagId == 'asian') (b) => '$b/?search=asian&page=$p',
          if (tagId == 'best') (b) => '$b/?id=most_rated&page=$p',
          if (tagId == 'hot') (b) => '$b/?id=hottest&page=$p',
        ];
      case 'youporn':
        return [
          if (tagId == 'new') (b) => '$b/browse/time/?page=$p',
          if (tagId == 'asian') (b) => '$b/category/asian/?page=$p',
          if (tagId == 'best') (b) => '$b/browse/rating/?page=$p',
          if (tagId == 'hot') (b) => '$b/popular/?page=$p',
        ];
      case 'spankbang':
        return [
          if (tagId == 'new') (b) => '$b/new_videos/$p/',
          if (tagId == 'asian') (b) => '$b/s/asian/$p/',
          if (tagId == 'best') (b) => '$b/top_videos/$p/',
          if (tagId == 'hot') (b) => '$b/trending_videos/$p/',
        ];
      case 'freeporn':
        return [
          if (tagId == 'new') (b) => '$b/videos?sort=new&page=$p',
          if (tagId == 'asian') (b) => '$b/search/asian?page=$p',
          if (tagId == 'best') (b) => '$b/videos?sort=rating&page=$p',
          if (tagId == 'hot') (b) => '$b/videos?sort=popular&page=$p',
          (b) => '$b/videos?page=$p',
        ];
      case 'tnaflix':
        return [
          if (tagId == 'new') (b) => '$b/new/$p',
          if (tagId == 'asian') (b) => '$b/search/asian/$p',
          if (tagId == 'best') (b) => '$b/top-rated/$p',
          if (tagId == 'hot') (b) => '$b/popular/$p',
          (b) => '$b/videos/$p',
        ];
      case 'stripchat':
        return [
          (b) =>
              '$b/api/front/models?limit=60&offset=${(p - 1) * 60}&primaryTag=${tagId == 'asia' ? 'asian' : 'girls'}&sortBy=${tagId == 'new' ? 'new' : 'stripRanking'}',
        ];
      case 'chaturbate':
        return [
          (b) =>
              '$b/api/ts/roomlist/room-list/?limit=90&offset=${(p - 1) * 90}&keywords=${tagId == 'asia' ? 'asian' : ''}',
        ];
      default:
        return [
          (b) => '$b/videos?page=$p&sort=$tagId',
          (b) => '$b/?page=$p&sort=$tagId',
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
        return [(b) => '$b/search/$enc${p > 1 ? '?page=$p' : ''}'];
      case 'eporner':
        return [(b) => '$b/search/$enc/${p > 1 ? '$p/' : ''}'];
      case 'freeporn':
        return [
          (b) => '$b/search/$enc?page=$p',
          (b) => '$b/videos?search=$enc&page=$p',
        ];
      case 'spankbang':
        return [(b) => '$b/s/$enc/${p > 1 ? '$p/' : ''}'];
      case 'jable':
        return [(b) => '$b/search/$enc/${p > 1 ? '$p/' : ''}'];
      case 'missav':
        return [(b) => '$b/search/$enc?page=$p'];
      case 'youporn':
        return [(b) => '$b/search/?query=$enc&page=$p'];
      case 'redtube':
        return [(b) => '$b/?search=$enc&page=$p'];
      case 'tnaflix':
        return [
          (b) => '$b/search?what=$enc&page=$p',
          (b) => '$b/search/$enc/$p',
        ];
      case 'javmix':
      case 'javgg':
      case 'bestjavporn':
        return [(b) => '$b/page/$p/?s=$enc', (b) => '$b/?s=$enc&paged=$p'];
      case 'av01':
        return [
          (b) => '$b/api/v1/videos/search?q=$enc&page=$p&limit=40',
          (b) => '$b/search?q=$enc&page=$p',
        ];
      case '7mmtv':
        return [
          (b) => '$b/zh/search?q=$enc&page=$p',
          (b) => '$b/zh/search/$enc/$p.html',
        ];
      case 'our55':
      case 'xqq88':
        return [
          (b) => '$b/index.php/vod/search/page/$p/wd/$enc.html',
          (b) => '$b/vod/search/page/$p/wd/$enc.html',
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
    var chunks = html.split(
      RegExp(
        r'(?=<div[^>]+class="[^"]*(?:video|thumb|item|card|post|movie|list-item)[^"]*")',
        caseSensitive: false,
      ),
    );
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
        final aText = RegExp(r'>\s*([^<>]{4,120})\s*<').firstMatch(chunk);
        if (aText != null) title = _cleanTitle(aText.group(1)!);
      }
      if (title == null || title.length < 2) {
        final slug = key.split('/').where((e) => e.isNotEmpty).last;
        title = Uri.decodeComponent(
          slug,
        ).replaceAll(RegExp(r'[-_]+'), ' ').trim();
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

      out.add(VideoItem(url: abs, title: title, duration: '-', thumb: thumb));
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
            RegExp(r'/index\.php/vod/').hasMatch(h) ||
            RegExp(r'/video/[a-f0-9]{16,}').hasMatch(h) ||
            RegExp(r'/(chinese|mosaic|nocode|western)/[a-z0-9]').hasMatch(h) ||
            RegExp(r'/video[s]?/\d').hasMatch(h) ||
            RegExp(r'/\d{3,}\.html').hasMatch(h);
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
            ![
              'female-cams',
              'male-cams',
              'couples',
              'tags',
              'accounts',
              'auth',
            ].contains(parts.first);
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

  String? _metaContent(String html, Set<String> names) {
    final tags =
        RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html);
    for (final tag in tags) {
      final attrs = <String, String>{};
      for (final attr in RegExp(
        r'''([:\w-]+)\s*=\s*["']([^"']*)["']''',
        caseSensitive: false,
      ).allMatches(tag.group(0)!)) {
        attrs[attr.group(1)!.toLowerCase()] = attr.group(2)!;
      }
      final name =
          (attrs['property'] ?? attrs['name'] ?? attrs['itemprop'] ?? '')
              .toLowerCase();
      if (names.contains(name)) {
        final value = attrs['content']?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _extractTitle(String html) {
    final meta = _metaContent(html, {'og:title', 'twitter:title'});
    if (meta != null) return _cleanTitle(meta);
    final t = RegExp(
      r'<title>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (t != null) {
      var s = _cleanTitle(t.group(1)!);
      s = s.split(RegExp(r'\s[-|–—]\s')).first.trim();
      if (s.length >= 2) return s;
    }
    return null;
  }

  String? _extractThumb(String html) {
    return _metaContent(html, {
      'og:image',
      'og:image:url',
      'twitter:image',
      'thumbnailurl',
    });
  }

  String? _resolvedThumb(String html, String pageUrl) {
    final thumb = _extractThumb(html);
    return thumb == null ? null : _abs(pageUrl, thumb);
  }

  List<StreamQuality> _extractStreams(String html, String base) {
    final streams = <StreamQuality>[];
    final seen = <String>{};

    void add(String? u, {int w = 0, int h = 0}) {
      if (u == null || u.isEmpty) return;
      var url = u
          .replaceAll(r'\/', '/')
          .replaceAll(r'\u002F', '/')
          .replaceAll(r'\u002f', '/')
          .replaceAll(r'\u003A', ':')
          .replaceAll(r'\u003a', ':')
          .replaceAll(r'\u0026', '&')
          .replaceAll('&amp;', '&')
          .trim();
      if (url.startsWith('//')) url = 'https:$url';
      if (!url.startsWith('http')) url = _abs(base, url);
      // Skip obvious non-media / short teasers
      final low = url.toLowerCase();
      if (low.contains('.js') ||
          low.contains('.css') ||
          low.contains('favicon') ||
          RegExp(r'\.(?:jpg|jpeg|png|gif|webp|svg)(?:[?#]|$)').hasMatch(low) ||
          low.contains('trailer') ||
          low.contains('/preview') ||
          low.contains('mediabook') ||
          RegExp(r'[_-](9|10|15)s[_.-]').hasMatch(low)) {
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
      r'''["'](https?:\\?/\\?/[^"'\s]+\.m3u8[^"'\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(m.group(1)?.replaceAll(r'\/', '/'), h: 720);
    }
    // HLS relative / escaped
    for (final m in RegExp(
      r'''["']([^"'\s]+\.m3u8[^"'\s]*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1);
      if (u != null && !u.startsWith('data:')) add(u, h: 720);
    }
    // m3u8 without quotes nearby (packed)
    for (final m in RegExp(
      r'(https?:\\?/\\?/[^\s"'
      '<>]+\.m3u8[^\s"'
      '<>]*)',
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
    add(
      _metaContent(html, {'og:video', 'og:video:url', 'twitter:player:stream'}),
      h: 720,
    );

    for (final m in RegExp(
      r'''<source[^>]+(?:src|data-src|data-lazy-src)=["']([^"']+)["']''',
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
      r'''["'](?:file|videoUrl|video_url|stream|streamUrl|playUrl|hls|hlsUrl|hls_url|m3u8)["']\s*:\s*["']([^"']+)["']''',
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

    // MacCMS / Chinese portals: accept direct media only. Parser endpoints are
    // resolved asynchronously by _resolveMacCmsPlayer.
    final blob = _macCmsPlayerBlob(html);
    if (blob != null) {
      final um = RegExp(
        r'''["']url["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(blob);
      if (um != null) {
        final encrypt = int.tryParse(
              RegExp(
                    r'''["']encrypt["']\s*:\s*["']?(\d+)''',
                  ).firstMatch(blob)?.group(1) ??
                  '',
            ) ??
            0;
        final u = _decodeMacCmsUrl(um.group(1)!, encrypt);
        if (_looksLikeMediaUrl(u)) add(u, h: 720);
      }
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
        .replaceAll(r'\u002f', '/')
        .replaceAll(r'\u003A', ':')
        .replaceAll(r'\u003a', ':')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\x2F', '/')
        .replaceAll(r'\x2f', '/')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#x22;', '"')
        .replaceAll('&amp;', '&');
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

    final room = _usernameFromUrl(pageUrl) ?? '';

    // Chaturbate: edge HLS + room Dossier API (live only, not VOD shows)
    if (site.id == 'chaturbate') {
      for (final m in RegExp(
        r'''https?:\\?/\\?/[^\s"'<>]*(?:playlist|live|amic|edge)[^\s"'<>]*\.m3u8[^\s"'<>]*''',
        caseSensitive: false,
      ).allMatches(html)) {
        var u = m.group(0)!.replaceAll(r'\/', '/');
        if (u.startsWith('//')) u = 'https:$u';
        // Skip non-live VOD / sex-show replays when possible
        final low = u.toLowerCase();
        if (low.contains('record') || low.contains('/vod/')) continue;
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

      if (room.isNotEmpty) {
        final apis = [
          '$base/api/chatvideocontext/$room/',
          '$base/$room/',
          'https://chaturbate.com/api/chatvideocontext/$room/',
        ];
        for (final api in apis) {
          try {
            final raw = await _getHtml(
              api,
              headers: {
                ...AppHttpHeaders.forSite(base),
                'Referer': pageUrl,
                'Accept': 'application/json,text/html,*/*',
                'X-Requested-With': 'XMLHttpRequest',
              },
            );
            for (final m in RegExp(
              r'''https?:\\?/\\?/[^\s"'<>]+\.m3u8[^\s"'<>]*''',
              caseSensitive: false,
            ).allMatches(raw)) {
              var u = m.group(0)!.replaceAll(r'\/', '/');
              streams.add(StreamQuality(width: 1280, height: 720, url: u));
            }
            final hs = RegExp(
              r'''hls_source["']?\s*[:=]\s*["']([^"']+)["']''',
              caseSensitive: false,
            ).firstMatch(raw);
            if (hs != null) {
              var u = hs.group(1)!.replaceAll(r'\/', '/');
              if (u.startsWith('//')) u = 'https:$u';
              streams.add(StreamQuality(width: 1280, height: 720, url: u));
            }
            if (streams.isNotEmpty) break;
          } catch (_) {}
        }
      }
    }

    // Stripchat / xHamsterLive: doppiocdn HLS by model username
    if (site.id == 'stripchat') {
      for (final m in RegExp(
        r'''https?:\\?/\\?/[^\s"'<>]*\.m3u8[^\s"'<>]*''',
        caseSensitive: false,
      ).allMatches(html)) {
        final u = m.group(0)!.replaceAll(r'\/', '/');
        streams.add(StreamQuality(width: 1280, height: 720, url: u));
      }
      // streamName in initial state
      final sn = RegExp(
        r'''["'](?:streamName|hlsStreamUrl|hlsPlaylist|hlsUrl|manifestUrl|streamUrl|webcamUrl)["']\s*:\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (sn != null) {
        var v = sn.group(1)!.replaceAll(r'\/', '/');
        if (v.contains('.m3u8')) {
          if (v.startsWith('//')) v = 'https:$v';
          if (!v.startsWith('http')) v = _abs(base, v);
          streams.add(StreamQuality(width: 1280, height: 720, url: v));
        } else if (room.isNotEmpty || v.isNotEmpty) {
          final name = v.isNotEmpty ? v : room;
          // Common doppiocdn edge patterns
          for (final u in [
            'https://edge-hls.doppiocdn.com/hls/$name/master/${name}_auto.m3u8',
            'https://edge-hls.doppiocdn.org/hls/$name/master/${name}_auto.m3u8',
            'https://media-hls.doppiocdn.com/hls/$name/master/${name}_auto.m3u8',
            'https://edge-hls.doppiocdn.com/hls/$name/master/$name.m3u8',
            'https://edge-hls.doppiocdn.org/hls/$name/master/$name.m3u8',
            'https://media-hls.doppiocdn.com/hls/$name/master/$name.m3u8',
          ]) {
            streams.add(StreamQuality(width: 1280, height: 720, url: u));
          }
        }
      }

      // model view API
      if (room.isNotEmpty) {
        try {
          final raw = await _getHtml(
            '$base/api/front/v2/models/username/$room/cam',
            headers: {
              ...AppHttpHeaders.forSite(base),
              'Accept': 'application/json',
              'Referer': pageUrl,
            },
          );
          for (final m in RegExp(
            r'''https?:\\?/\\?/[^\s"'<>]+\.m3u8[^\s"'<>]*''',
            caseSensitive: false,
          ).allMatches(raw)) {
            streams.add(
              StreamQuality(
                width: 1280,
                height: 720,
                url: m.group(0)!.replaceAll(r'\/', '/'),
              ),
            );
          }
          final apiField = RegExp(
            r'''["'](?:streamName|hlsStreamUrl|hlsPlaylist|hlsUrl|manifestUrl|streamUrl|webcamUrl)["']\s*:\s*["']([^"']+)["']''',
            caseSensitive: false,
          ).firstMatch(raw);
          if (apiField != null) {
            var value = apiField.group(1)!.replaceAll(r'\/', '/');
            if (value.contains('.m3u8')) {
              if (value.startsWith('//')) value = 'https:$value';
              if (!value.startsWith('http')) value = _abs(base, value);
              streams.add(
                StreamQuality(width: 1280, height: 720, url: value),
              );
            } else if (value.isNotEmpty) {
              for (final candidate in [
                'https://edge-hls.doppiocdn.com/hls/$value/master/${value}_auto.m3u8',
                'https://edge-hls.doppiocdn.org/hls/$value/master/${value}_auto.m3u8',
              ]) {
                streams.add(
                  StreamQuality(width: 1280, height: 720, url: candidate),
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // Dedup + drop obvious non-live VOD if live candidates exist
    final seen = <String>{};
    final live = <StreamQuality>[];
    final other = <StreamQuality>[];
    for (final s in streams) {
      if (!seen.add(s.url)) continue;
      final low = s.url.toLowerCase();
      if (low.contains('.m3u8') &&
          !low.contains('/vod/') &&
          !low.contains('record')) {
        live.add(s);
      } else {
        other.add(s);
      }
    }
    return live.isNotEmpty ? live : other;
  }
}

class _FetchedPage {
  const _FetchedPage({
    required this.html,
    required this.url,
    required this.base,
  });

  final String html;
  final String url;
  final String base;
}
