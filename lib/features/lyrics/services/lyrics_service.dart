import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A single timestamped line in a synchronized song text.
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text;

  @override
  int get hashCode => timestamp.hashCode ^ text.hashCode;

  @override
  String toString() => 'LyricLine(${timestamp.inMilliseconds}ms: "$text")';
}

/// Lyrics representation with synchronized and fallback plain text.
class LyricsModel {
  final bool isSynced;
  final List<LyricLine> lines;
  final String? plainLyrics;

  const LyricsModel({
    required this.isSynced,
    required this.lines,
    this.plainLyrics,
  });

  bool get isEmpty => lines.isEmpty && (plainLyrics == null || plainLyrics!.isEmpty);
  bool get isNotEmpty => !isEmpty;
}

/// Service for retrieving and parsing lyrics from the public open LRCLIB API.
class LyricsService {
  final http.Client _httpClient;

  LyricsService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static final RegExp _lrcLinePattern = RegExp(
    r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{2,3}))?\](.*)$',
  );

  /// Fetches synchronized or plain lyrics for the specified track from LRCLIB.
  Future<LyricsModel?> fetchLyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _cleanMetadata(title);
    final cleanArtist = _cleanMetadata(artist);

    // 1. Exact match attempt via /api/get
    try {
      final queryParams = <String, String>{
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (duration != null && duration.inSeconds > 0)
          'duration': duration.inSeconds.toString(),
      };

      final uri = Uri.https('lrclib.net', '/api/get', queryParams);
      final response = await _httpClient.get(
        uri,
        headers: {
          HttpHeaders.userAgentHeader: 'NCmus/1.0 (https://github.com/ncmus)',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          final model = _parseLrcLibResponse(data);
          if (model != null && model.isNotEmpty) return model;
        }
      }
    } catch (_) {
      // Fallback to fuzzy search endpoint
    }

    // 2. Fallback search attempt via /api/search
    try {
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'q': '$cleanArtist $cleanTitle',
      });

      final response = await _httpClient.get(
        searchUri,
        headers: {
          HttpHeaders.userAgentHeader: 'NCmus/1.0 (https://github.com/ncmus)',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final dynamic results = jsonDecode(utf8.decode(response.bodyBytes));
        if (results is List && results.isNotEmpty) {
          // Prefer results that contain synced lyrics
          for (final item in results) {
            if (item is Map<String, dynamic>) {
              final synced = item['syncedLyrics'] as String?;
              if (synced != null && synced.trim().isNotEmpty) {
                final model = _parseLrcLibResponse(item);
                if (model != null && model.isNotEmpty) return model;
              }
            }
          }

          // Otherwise return first valid response
          final first = results.first;
          if (first is Map<String, dynamic>) {
            return _parseLrcLibResponse(first);
          }
        }
      }
    } catch (_) {
      // Return null on failure
    }

    return null;
  }

  LyricsModel? _parseLrcLibResponse(Map<String, dynamic> data) {
    final syncedRaw = data['syncedLyrics'] as String?;
    final plainRaw = data['plainLyrics'] as String?;

    if (syncedRaw != null && syncedRaw.trim().isNotEmpty) {
      final parsedLines = parseLrc(syncedRaw);
      if (parsedLines.isNotEmpty) {
        return LyricsModel(
          isSynced: true,
          lines: parsedLines,
          plainLyrics: plainRaw,
        );
      }
    }

    if (plainRaw != null && plainRaw.trim().isNotEmpty) {
      final lines = plainRaw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => LyricLine(timestamp: Duration.zero, text: line))
          .toList();

      return LyricsModel(
        isSynced: false,
        lines: lines,
        plainLyrics: plainRaw,
      );
    }

    return null;
  }

  /// Parses raw LRC format into a sorted list of [LyricLine]s.
  List<LyricLine> parseLrc(String rawLrc) {
    final result = <LyricLine>[];
    final lines = rawLrc.split('\n');

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final match = _lrcLinePattern.firstMatch(trimmed);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final sub = match.group(3);

        int milliseconds = 0;
        if (sub != null && sub.isNotEmpty) {
          if (sub.length == 2) {
            milliseconds = (int.tryParse(sub) ?? 0) * 10;
          } else {
            milliseconds = int.tryParse(sub) ?? 0;
          }
        }

        final text = (match.group(4) ?? '').trim();
        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        result.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  String _cleanMetadata(String input) {
    return input
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s*ft\.?.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*feat\.?.*', caseSensitive: false), '')
        .trim();
  }

  void dispose() {
    _httpClient.close();
  }
}
