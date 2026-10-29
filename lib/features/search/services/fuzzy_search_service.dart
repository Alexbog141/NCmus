import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/database/database_service.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../scraper/models/scraped_track.dart';

/// Service providing spelling correction, fuzzy search and fallback tokenization
/// for robust track discovery across music mirrors.
class FuzzySearchService {
  final ScraperEngine scraperEngine;
  final http.Client _httpClient;
  final DatabaseService _dbService;

  FuzzySearchService({
    required this.scraperEngine,
    http.Client? httpClient,
    DatabaseService? dbService,
  })  : _httpClient = httpClient ?? http.Client(),
        _dbService = dbService ?? DatabaseService.instance;

  static const List<String> _stopWords = [
    'feat',
    'ft',
    'prod',
    'remix',
    'the',
    'and',
    'official',
    'audio',
    'video',
    'clip',
    'music',
  ];

  /// Suggests a corrected query using public suggestion endpoints and
  /// local database matching.
  Future<String> correctQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return trimmed;

    // 1. Try DuckDuckGo / Google Suggest API
    try {
      final webCorrection = await _fetchWebSuggestion(trimmed);
      if (webCorrection != null &&
          webCorrection.trim().isNotEmpty &&
          webCorrection.toLowerCase() != trimmed.toLowerCase()) {
        return webCorrection.trim();
      }
    } catch (_) {
      // Suggest endpoint failure is non-fatal.
    }

    // 2. Try local SQLite fuzzy match across known titles and artists
    try {
      final localCorrection = await _findLocalCorrection(trimmed);
      if (localCorrection != null) {
        return localCorrection;
      }
    } catch (_) {
      // Best-effort local correction.
    }

    return trimmed;
  }

  /// Combined search flow:
  /// 1. Original query
  /// 2. If empty: spell-corrected query
  /// 3. If still empty: significant token fallback
  Future<List<ScrapedTrack>> robustSearch(String query) async {
    final raw = query.trim();
    if (raw.isEmpty) return const [];

    // Stage 1: Search raw query
    try {
      final primaryResults = await scraperEngine.searchAll(raw);
      if (primaryResults.isNotEmpty) {
        return primaryResults;
      }
    } catch (_) {
      // Proceed to fallback on network error or zero results.
    }

    // Stage 2: Correct query spelling and re-search
    final corrected = await correctQuery(raw);
    if (corrected.toLowerCase() != raw.toLowerCase()) {
      try {
        final correctedResults = await scraperEngine.searchAll(corrected);
        if (correctedResults.isNotEmpty) {
          return correctedResults;
        }
      } catch (_) {}
    }

    // Stage 3: Split into significant words and search by most relevant tokens
    final tokens = _extractSignificantTokens(raw);
    if (tokens.isNotEmpty) {
      final aggregated = <String, ScrapedTrack>{};

      for (final token in tokens.take(2)) {
        try {
          final tokenResults = await scraperEngine.searchAll(token);
          for (final track in tokenResults) {
            aggregated.putIfAbsent(track.deduplicationKey, () => track);
          }
          if (aggregated.length >= 10) break;
        } catch (_) {}
      }

      if (aggregated.isNotEmpty) {
        return aggregated.values.toList();
      }
    }

    return const [];
  }

  Future<String?> _fetchWebSuggestion(String query) async {
    // Google Suggest API (Firefox client returns pure JSON array: [query, [suggestions...]])
    final uri = Uri.parse(
      'https://suggestqueries.google.com/complete/search?client=firefox&q=${Uri.encodeComponent(query)}',
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        HttpHeaders.userAgentHeader:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36',
      },
    ).timeout(const Duration(milliseconds: 1800));

    if (response.statusCode == 200) {
      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is List && decoded.length > 1 && decoded[1] is List) {
        final suggestions = decoded[1] as List;
        if (suggestions.isNotEmpty) {
          final first = suggestions.first.toString();
          if (first.trim().isNotEmpty) {
            return first;
          }
        }
      }
    }

    return null;
  }

  Future<String?> _findLocalCorrection(String query) async {
    final tracks = await _dbService.getAllTracks();
    if (tracks.isEmpty) return null;

    final queryLower = query.toLowerCase();
    String? bestMatch;
    int minDistance = 999;

    for (final track in tracks) {
      final candidates = [track.title.toLowerCase(), track.artist.toLowerCase()];
      for (final candidate in candidates) {
        final dist = _levenshteinDistance(queryLower, candidate);
        // Match if within reasonable typo range (1 to 3 characters difference)
        if (dist > 0 && dist <= 3 && dist < minDistance) {
          minDistance = dist;
          bestMatch = candidate == track.title.toLowerCase()
              ? track.title
              : track.artist;
        }
      }
    }

    return bestMatch;
  }

  List<String> _extractSignificantTokens(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Zа-яА-Я0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) =>
            token.length >= 3 && !_stopWords.contains(token.toLowerCase()))
        .toList();
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce(
            (curr, next) => curr < next ? curr : next);
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[s2.length];
  }

  void dispose() {
    _httpClient.close();
  }
}
