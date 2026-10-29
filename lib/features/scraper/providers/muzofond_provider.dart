import 'dart:async';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/scraped_track.dart';
import '../services/mirror_resolver.dart';
import 'music_provider.dart';

class MuzofondProvider implements MusicProvider {
  static const String providerName = 'Muzofond';
  static const String defaultBaseUrl = 'https://muzofond.fm';
  static const String htmlSignature = '.item';

  final MirrorResolver _mirrorResolver;
  final http.Client _client;
  final bool _closeClientOnDispose;

  MuzofondProvider({
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

    // If default mirror fails, try available fallbacks from MirrorResolver
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
    final searchUri = Uri.parse('$baseUrl/search/${Uri.encodeComponent(query)}');

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
    final trackElements = document.querySelectorAll('li.item, .item');
    final List<ScrapedTrack> results = [];

    for (final element in trackElements) {
      final trackId = element.attributes['data-id'];
      final artist = element.querySelector('.artist')?.text.trim() ?? '';
      final title = element.querySelector('.track')?.text.trim() ?? '';

      // Direct MP3 link is placed in data-url on the play button element
      final playEl = element.querySelector('li.play') ??
          element.querySelector('.play') ??
          element.querySelector('[data-url]');
      String streamUrl = playEl?.attributes['data-url']?.trim() ?? '';

      if (streamUrl.isEmpty) {
        // Fallback: check download button
        final dlEl = element.querySelector('a.dl') ??
            element.querySelector('a[href*=".mp3"]');
        final href = dlEl?.attributes['href']?.trim() ?? '';
        if (href.isNotEmpty) {
          streamUrl = href;
        }
      }

      // Timing extraction
      Duration duration = Duration.zero;
      final rawSecStr = element.attributes['data-duration'];
      if (rawSecStr != null && rawSecStr.isNotEmpty) {
        final sec = int.tryParse(rawSecStr);
        if (sec != null && sec > 0) {
          duration = Duration(seconds: sec);
        }
      }
      if (duration == Duration.zero) {
        final durationText = element.querySelector('.duration')?.text.trim() ?? '';
        if (durationText.isNotEmpty) {
          duration = _parseDuration(durationText);
        }
      }

      // Cover image extraction
      String? coverUrl = element.attributes['data-img']?.trim();
      if (coverUrl != null && coverUrl.isNotEmpty) {
        if (coverUrl.startsWith('//')) {
          coverUrl = 'https:$coverUrl';
        } else if (coverUrl.startsWith('/')) {
          coverUrl = '$baseUrl$coverUrl';
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
