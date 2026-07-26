import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/source_catalog.dart';

/// Favicon / site mark for catalog entries.
class SiteLogo extends StatelessWidget {
  const SiteLogo({
    super.key,
    required this.site,
    this.size = 44,
  });

  final SiteDef site;
  final double size;

  String get _faviconUrl {
    final host = Uri.tryParse(site.primaryHost)?.host;
    if (host == null || host.isEmpty) {
      return '';
    }
    // Public favicon proxy — works without CORS issues in Flutter network image.
    return 'https://www.google.com/s2/favicons?domain=$host&sz=128';
  }

  @override
  Widget build(BuildContext context) {
    final url = _faviconUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF2A2A2A),
        child: url.isEmpty
            ? _Letter(site: site, size: size)
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => _Letter(site: site, size: size),
                errorWidget: (_, __, ___) => _Letter(site: site, size: size),
              ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.site, required this.size});

  final SiteDef site;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: Color(site.color).withValues(alpha: 0.85),
      child: Text(
        site.letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
