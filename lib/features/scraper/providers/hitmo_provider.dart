import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/scraped_track.dart';
import '../services/mirror_resolver.dart';
import 'music_provider.dart';

class HitmoProvider implements MusicProvider {
  static const String providerName = 'Hitmo';
  static const String defaultBaseUrl = 'https://hitmo.me';
  static const String htmlSignature = '.tracks__item';

  final MirrorResolver _mirrorResolver;
  final http.Client _client;
  final bool _closeClientOnDispose;

  HitmoProvider({
    MirrorResolver? mirrorResolver,
    http.Client? client,
  })  : _mirrorResolver = mirrorResolver ?? MirrorResolver(),
        _client = client ?? http.Client(),
        _closeClientOnDispose = client == null;

  @override
  String get name => providerName;

  @override
  String get currentBaseUrl => _mirrorResolver.getCurrentBaseUrl(name).isNotEmpty
      ? _mirrorResolver.getCurrentBaseUrl(name)
      : defaultBaseUrl;

  @override
  Future<bool> validateMirror(String baseUrl) {
    return _mirrorResolver.validateMirror(
      baseUrl,
      expectedSignature: htmlSignature,
      client: _client,
    );
  }

  @override
  Future<List<ScrapedTrack>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    String activeBaseUrl = currentBaseUrl;
    if (!_mirrorResolver.isHostAvailable(activeBaseUrl)) {
      activeBaseUrl = await _mirrorResolver.resolveActiveMirror(
        name,
        expectedSignature: htmlSignature,
        client: _client,
      );
    }

    final tracks = await _trySearchOnMirror(activeBaseUrl, trimmedQuery);
    if (tracks.isNotEmpty) {
      return tracks;
    }

    // If the active mirror yielded an error or 0 tracks due to connection issue,
    // try fallback mirrors through MirrorResolver
    final mirrors = _mirrorResolver.getMirrorsFor(name);
    for (final mirror in mirrors) {
      if (mirror == activeBaseUrl) continue;
      if (!_mirrorResolver.isHostAvailable(mirror)) continue;

      final fallbackTracks = await _trySearchOnMirror(mirror, trimmedQuery);
      if (fallbackTracks.isNotEmpty) {
        _mirrorResolver.setActiveMirror(name, mirror);
        return fallbackTracks;
      }
    }

    return const [];
  }

  Future<List<ScrapedTrack>> _trySearchOnMirror(
    String baseUrl,
    String query,
  ) async {
    final searchUri = Uri.parse('$baseUrl/search?q=${Uri.encodeComponent(query)}');

    try {
      final response = await _client.get(
        searchUri,
        headers: {
          'User-Agent': MirrorResolver.defaultUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          'Referer': baseUrl,
        },
      ).timeout(MirrorResolver.defaultTimeout);

      if (response.statusCode != 200) {
        _mirrorResolver.recordFailure(baseUrl);
        return const [];
      }

      final htmlBody = response.body;
      if (!_mirrorResolver.verifyHtmlSignature(htmlBody, htmlSignature)) {
        _mirrorResolver.recordFailure(baseUrl);
        return const [];
      }

      _mirrorResolver.recordSuccess(baseUrl);
      return _parseHtml(htmlBody, baseUrl);
    } on TimeoutException {
      _mirrorResolver.recordFailure(baseUrl);
      return const [];
    } on SocketException {
      _mirrorResolver.recordFailure(baseUrl);
      return const [];
    } catch (_) {
      _mirrorResolver.recordFailure(baseUrl);
      return const [];
    }
  }

  List<ScrapedTrack> _parseHtml(String html, String baseUrl) {
    final document = html_parser.parse(html);
    final trackElements = document.querySelectorAll('.tracks__item');
    final List<ScrapedTrack> results = [];

    for (final element in trackElements) {
      String? trackId = element.attributes['data-musid'];
      String title = '';
      String artist = '';
      String streamUrl = '';
      String? coverUrl;
      Duration duration = Duration.zero;

      // Extract metadata from data-musmeta JSON if available
      final musmetaRaw = element.attributes['data-musmeta'];
      if (musmetaRaw != null && musmetaRaw.isNotEmpty) {
        try {
          final dynamic parsed = jsonDecode(musmetaRaw);
          if (parsed is Map<String, dynamic>) {
            title = (parsed['title'] as String?)?.trim() ?? '';
            artist = (parsed['artist'] as String?)?.trim() ?? '';
            streamUrl = (parsed['url'] as String?)?.trim() ?? '';
            coverUrl = (parsed['img'] as String?)?.trim();
            final metaId = (parsed['id'] as String?)?.trim();
            if (metaId != null && metaId.isNotEmpty) {
              trackId = metaId;
            }
          }
        } catch (_) {}
      }

      // Fallback extraction from DOM elements
      if (title.isEmpty) {
        title = element.querySelector('.track__title')?.text.trim() ?? '';
      }
      if (artist.isEmpty) {
        artist = element.querySelector('.track__desc')?.text.trim() ?? '';
      }

      if (streamUrl.isEmpty) {
        final downloadBtn = element.querySelector('a.track__download-btn');
        final href = downloadBtn?.attributes['href'];
        if (href != null && href.isNotEmpty) {
          streamUrl = href.trim();
        }
      }

      // Extract duration from .track__fulltime or .track__time
      final durationText =
          element.querySelector('.track__fulltime')?.text.trim() ??
              element.querySelector('.track__time')?.text.trim() ??
              '';
      if (durationText.isNotEmpty) {
        duration = _parseDuration(durationText);
      }

      // Extract cover URL from style attribute if missing
      if (coverUrl == null || coverUrl.isEmpty) {
        final imgEl = element.querySelector('.track__img');
        final style = imgEl?.attributes['style'] ?? '';
        final match = RegExp(r"url\(['\x22]?([^'\x22]+)['\x22]?\)").firstMatch(style);
        if (match != null) {
          coverUrl = match.group(1);
        }
      }

      // Normalize stream URL
      if (streamUrl.isNotEmpty) {
        if (streamUrl.startsWith('//')) {
          streamUrl = 'https:$streamUrl';
        } else if (streamUrl.startsWith('/')) {
          streamUrl = '$baseUrl$streamUrl';
        }
      }

      // Normalize cover URL
      if (coverUrl != null && coverUrl.isNotEmpty) {
        if (coverUrl.startsWith('//')) {
          coverUrl = 'https:$coverUrl';
        } else if (coverUrl.startsWith('/')) {
          coverUrl = '$baseUrl$coverUrl';
        }
      }

      if (title.isNotEmpty && streamUrl.isNotEmpty) {
        results.add(
          ScrapedTrack(
            id: trackId ?? streamUrl,
            title: title,
            artist: artist.isNotEmpty ? artist : 'Unknown Artist',
            duration: duration,
            streamUrl: streamUrl,
            coverUrl: coverUrl,
            sourceName: providerName,
          ),
        );
      }
    }

    return results;
  }

  Duration _parseDuration(String text) {
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return Duration.zero;
  }

  void dispose() {
    if (_closeClientOnDispose) {
      _client.close();
    }
  }
}
