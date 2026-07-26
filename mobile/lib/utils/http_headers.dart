/// Shared browser-like headers for CDN / site requests.
class AppHttpHeaders {
  /// Desktop Chrome — many adult CDNs reject bare Mobile UA or wrong Referer.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const Map<String, String> browser = {
    'User-Agent': userAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
            'image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
    'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7',
    'Accept-Encoding': 'gzip, deflate',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Sec-Ch-Ua':
        '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"Windows"',
  };

  /// Headers for a page fetch with correct site origin/referer.
  static Map<String, String> forSite(String baseUrl) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final origin = _origin(base) ?? base;
    return {
      ...browser,
      'Referer': '$origin/',
      'Origin': origin,
      'Sec-Fetch-Site': 'same-origin',
    };
  }

  /// Thumb / stream headers by media URL host (or page host).
  static Map<String, String> forMediaUrl(String? url, {String? pageUrl}) {
    final pageOrigin = _origin(pageUrl ?? '');
    final u = (url ?? '').toLowerCase();

    String? siteOrigin;
    if (u.contains('xvideos') ||
        u.contains('xvideos-cdn') ||
        u.contains('xnxx')) {
      siteOrigin = 'https://www.xvideos.com';
    } else if (u.contains('mitao') || u.contains('mitaohk') || u.contains('jipinvipplay')) {
      siteOrigin = 'https://mitaohk.com';
    } else if (u.contains('pornhub') ||
        u.contains('phncdn') ||
        u.contains('porncdn')) {
      siteOrigin = 'https://www.pornhub.com';
    } else if (u.contains('youporn') || u.contains('ypncdn')) {
      siteOrigin = 'https://www.youporn.com';
    } else if (u.contains('redtube') || u.contains('rdtcdn')) {
      siteOrigin = 'https://www.redtube.com';
    } else if (u.contains('eporner')) {
      siteOrigin = 'https://www.eporner.com';
    } else if (u.contains('spankbang')) {
      siteOrigin = 'https://spankbang.com';
    } else if (u.contains('xhamster')) {
      siteOrigin = 'https://xhamster.com';
    } else if (u.contains('chaturbate') ||
        u.contains('highwebmedia') ||
        u.contains('live.mmcdn')) {
      siteOrigin = 'https://chaturbate.com';
    } else if (u.contains('stripchat') ||
        u.contains('doppiocdn') ||
        u.contains('stripcdn')) {
      siteOrigin = 'https://stripchat.com';
    } else if (u.contains('jable')) {
      siteOrigin = 'https://jable.tv';
    } else if (u.contains('missav')) {
      siteOrigin = 'https://missav.ai';
    } else if (u.contains('bestjavporn') || u.contains('pornfhd')) {
      siteOrigin = 'https://www.bestjavporn.com';
    }

    siteOrigin ??= pageOrigin ?? _origin(url);

    if (siteOrigin != null && siteOrigin.isNotEmpty) {
      return {
        ...browser,
        'Referer': '$siteOrigin/',
        'Origin': siteOrigin,
        'Accept': '*/*',
        'Sec-Fetch-Dest': 'video',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site',
      };
    }
    return {
      ...browser,
      'Accept': '*/*',
    };
  }

  static String? _origin(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}';
      }
    } catch (_) {}
    return null;
  }
}
