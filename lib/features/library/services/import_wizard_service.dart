import 'dart:async';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../scraper/models/scraped_track.dart';
import '../../storage/models/track_entity.dart';

enum ImportMatchStatus {
  pending,
  exactMatch, // 🟢 100% совпадение (Δ <= 2s)
  disputed, // 🟡 Требуют внимания (каверы, разница во времени > 2s)
  notFound, // 🔴 Не найдено в открытой сети
}

class ImportTrackMatch {
  final String id;
  final String originalArtist;
  final String originalTitle;
  final Duration? originalDuration;

  ScrapedTrack? candidate;
  List<ScrapedTrack> alternativeCandidates;
  ImportMatchStatus status;

  ImportTrackMatch({
    required this.id,
    required this.originalArtist,
    required this.originalTitle,
    this.originalDuration,
    this.candidate,
    this.alternativeCandidates = const [],
    this.status = ImportMatchStatus.pending,
  });

  String get deduplicationKey =>
      '${originalArtist.toLowerCase().trim()}|${originalTitle.toLowerCase().trim()}';

  int get deltaSeconds {
    if (candidate == null || originalDuration == null) return 0;
    return (candidate!.duration.inSeconds - originalDuration!.inSeconds).abs();
  }

  String get deltaBadgeText {
    if (candidate == null || originalDuration == null) return 'Δ 0s';
    final diff = candidate!.duration.inSeconds - originalDuration!.inSeconds;
    if (diff.abs() <= 2) return 'Δ <= 2s';
    final sign = diff > 0 ? '+' : '-';
    final m = diff.abs() ~/ 60;
    final s = (diff.abs() % 60).toString().padLeft(2, '0');
    return '$sign$m:$s';
  }
}

class ImportScanProgress {
  final int processed;
  final int total;
  final String currentQuery;
  final int exactCount;
  final int disputedCount;
  final int notFoundCount;

  const ImportScanProgress({
    required this.processed,
    required this.total,
    required this.currentQuery,
    required this.exactCount,
    required this.disputedCount,
    required this.notFoundCount,
  });

  double get ratio => total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
}

/// Service that coordinates multi-step staging, scraping, dispute resolution,
/// and safe commit into SQLite with zero-garbage cleanup.
class ImportWizardService {
  static final ImportWizardService instance = ImportWizardService._internal();

  final DatabaseService _dbService;

  List<ImportTrackMatch> _stagedMatches = [];
  bool _isScanning = false;
  StreamController<ImportScanProgress>? _progressController;

  ImportWizardService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  ImportWizardService._internal() : _dbService = DatabaseService.instance;

  List<ImportTrackMatch> get stagedMatches => List.unmodifiable(_stagedMatches);
  bool get isScanning => _isScanning;

  int get totalCount => _stagedMatches.length;
  int get exactCount => _stagedMatches
      .where((m) => m.status == ImportMatchStatus.exactMatch)
      .length;
  int get disputedCount => _stagedMatches
      .where((m) => m.status == ImportMatchStatus.disputed)
      .length;
  int get notFoundCount => _stagedMatches
      .where((m) => m.status == ImportMatchStatus.notFound)
      .length;

  /// Full isolation & cleanup: wipes any staged data, resets controllers and memory.
  Future<void> wipeStagingSession() async {
    _isScanning = false;
    _stagedMatches = [];
    if (_progressController != null && !_progressController!.isClosed) {
      await _progressController!.close();
    }
    _progressController = null;
  }

  /// Parses raw text into structured track matches.
  List<ImportTrackMatch> parseRawInput(String rawText) {
    if (rawText.trim().isEmpty) {
      _stagedMatches = [];
      return const [];
    }

    final lines = rawText.split(RegExp(r'[\r\n]+'));
    final unique = <String, ImportTrackMatch>{};

    for (var rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;

      // 1. Strip URLs
      line = line.replaceAll(RegExp(r'https?:\/\/\S+'), '').trim();
      if (line.isEmpty) continue;

      // 2. Strip leading numbers
      line = line.replaceAll(RegExp(r'^[#\[\(]?\d+[\.\)\]]?\s*'), '').trim();

      // 3. Extract & strip duration if present e.g. "03:45", "(3:20)", "[04:12]"
      Duration? parsedDuration;
      final durationMatch =
          RegExp(r'[\(\[]?(\d{1,2}):(\d{2})[\)\]]?').firstMatch(line);
      if (durationMatch != null) {
        final minutes = int.tryParse(durationMatch.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(durationMatch.group(2) ?? '0') ?? 0;
        parsedDuration = Duration(minutes: minutes, seconds: seconds);
      }
      line = line.replaceAll(RegExp(r'[\(\[]?\d{1,2}:\d{2}[\)\]]?'), '').trim();

      String artist = '';
      String title = '';

      if (line.contains('\t')) {
        final parts = line
            .split('\t')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          artist = parts[0];
          title = parts[1];
        } else if (parts.length == 1) {
          title = parts[0];
        }
      } else if (line.contains(' — ') ||
          line.contains(' – ') ||
          line.contains(' - ') ||
          line.contains('—')) {
        final parts = line
            .split(RegExp(r'\s*[—–\-]\s*'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          artist = parts[0];
          title = parts.sublist(1).join(' - ');
        }
      } else if (line.contains(',')) {
        final parts = line
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          artist = parts[0];
          title = parts.sublist(1).join(' ');
        }
      } else {
        title = line;
        artist = 'Unknown Artist';
      }

      artist = sanitizeQuery(artist);
      title = sanitizeQuery(title);

      if (title.isEmpty) continue;
      if (artist.isEmpty) artist = 'Unknown Artist';

      final item = ImportTrackMatch(
        id: 'stage_${unique.length}_${DateTime.now().microsecondsSinceEpoch}',
        originalArtist: artist,
        originalTitle: title,
        originalDuration: parsedDuration,
        status: ImportMatchStatus.pending,
      );

      unique[item.deduplicationKey] = item;
    }

    _stagedMatches = unique.values.toList();
    return _stagedMatches;
  }

  /// Deep search query sanitizer removing promotional tags, file extensions,
  /// producer tags, extra punctuation, em-dashes and collapsing whitespaces.
  static String sanitizeQuery(String text) {
    var clean = text;
    // Удаляем любые теги сайтов и мусор в скобках: [mp3uk.net], (mp3), [320kbps] и т.д.
    clean = clean.replaceAll(RegExp(r'\[.*?\]'), '');
    clean = clean.replaceAll(
      RegExp(r'\(.*?(prod|feat|rip|remaster|kbps|\.net|\.ru|\.com).*?\)',
          caseSensitive: false),
      '',
    );
    // Удаляем рекламные хвосты
    clean =
        clean.replaceAll(RegExp(r'prod\.by\s*\S+', caseSensitive: false), '');
    // Заменяем длинные тире, спецсимволы и многоточия на пробелы
    clean = clean.replaceAll(RegExp(r'[—–_]'), ' ');
    clean = clean.replaceAll(RegExp(r'\.{2,}'), '');
    clean = clean.replaceAll(RegExp(r'["«»\x27]'), '');
    // Схлопываем пробелы
    return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Helper to pick the best candidate matching within <= 2s delta or closest duration.
  static ScrapedTrack? findBestCandidate(
    List<ScrapedTrack> results,
    Duration? expectedDuration,
  ) {
    if (results.isEmpty) return null;
    if (expectedDuration != null && expectedDuration > Duration.zero) {
      for (final candidate in results) {
        if (candidate.duration > Duration.zero) {
          final diff =
              (candidate.duration.inSeconds - expectedDuration.inSeconds).abs();
          if (diff <= 2) {
            return candidate;
          }
        }
      }
      return null;
    }
    return results.first;
  }

  /// Multi-tier fallback pipeline with 3 attempts:
  /// 1. Cleaned full query "Artist Title"
  /// 2. Primary artist only "PrimaryArtist Title" (if multiple artists)
  /// 3. Title only (if length > 3)
  Future<ScrapedTrack?> resolveTrackWithFallbacks(
    String originalArtist,
    String originalTitle, {
    Duration? expectedDuration,
    ScraperEngine? scraperEngine,
  }) async {
    final engine = scraperEngine ?? ScraperEngine.instance;
    final cleanArtist = sanitizeQuery(originalArtist);
    final cleanTitle = sanitizeQuery(originalTitle);

    // Попытка 1: Очищенный полный запрос "Артист Название"
    var results = await engine.searchAll('$cleanArtist $cleanTitle'.trim());
    var match = findBestCandidate(results, expectedDuration);
    if (match != null) return match;

    // Попытка 2: Если артистов несколько (через запятую, &, feat, ft) — ищем только по первому артисту:
    final primaryArtist = cleanArtist
        .split(RegExp(r'[,&]|\s+feat\.?|\s+ft\.?', caseSensitive: false))
        .first
        .trim();
    if (primaryArtist != cleanArtist && primaryArtist.isNotEmpty) {
      results = await engine.searchAll('$primaryArtist $cleanTitle'.trim());
      match = findBestCandidate(results, expectedDuration);
      if (match != null) return match;
    }

    // Попытка 3: Если всё ещё 0 — ищем только по названию трека (часто в названии уже зашит артист или он уникален):
    if (cleanTitle.length > 3) {
      results = await engine.searchAll(cleanTitle);
      match = findBestCandidate(results, expectedDuration);
      if (match != null) return match;
    }

    return null;
  }

  /// Runs holographic radar matching via ScraperEngine with multi-tier fallback pipeline.
  Stream<ImportScanProgress> startScan({required ScraperEngine scraperEngine}) {
    _progressController?.close();
    _progressController = StreamController<ImportScanProgress>.broadcast();
    _isScanning = true;

    final controller = _progressController!;
    final total = _stagedMatches.length;

    Timer.run(() async {
      for (var i = 0; i < total; i++) {
        if (!_isScanning || controller.isClosed) break;

        final item = _stagedMatches[i];
        final cleanArtist = sanitizeQuery(item.originalArtist);
        final cleanTitle = sanitizeQuery(item.originalTitle);
        final displayQuery =
            cleanArtist.isNotEmpty ? '$cleanArtist - $cleanTitle' : cleanTitle;

        try {
          // Attempt 1: Full cleaned query
          var results =
              await scraperEngine.searchAll('$cleanArtist $cleanTitle'.trim());
          var match = findBestCandidate(results, item.originalDuration);
          List<ScrapedTrack> candidatesPool = results;

          // Attempt 2: If no exact match and multiple artists, search by primary artist
          if (match == null) {
            final primaryArtist = cleanArtist
                .split(
                    RegExp(r'[,&]|\s+feat\.?|\s+ft\.?', caseSensitive: false))
                .first
                .trim();
            if (primaryArtist != cleanArtist && primaryArtist.isNotEmpty) {
              final results2 = await scraperEngine
                  .searchAll('$primaryArtist $cleanTitle'.trim());
              final match2 = findBestCandidate(results2, item.originalDuration);
              if (match2 != null) {
                match = match2;
                candidatesPool = results2;
              } else if (candidatesPool.isEmpty) {
                candidatesPool = results2;
              }
            }
          }

          // Attempt 3: If still no exact match and candidates pool is empty, search title only
          if (match == null &&
              candidatesPool.isEmpty &&
              cleanTitle.length > 3) {
            final results3 = await scraperEngine.searchAll(cleanTitle);
            final match3 = findBestCandidate(results3, item.originalDuration);
            if (match3 != null) {
              match = match3;
              candidatesPool = results3;
            } else if (candidatesPool.isEmpty) {
              candidatesPool = results3;
            }
          }

          if (match != null) {
            // 🟢 100% exact match (delta <= 2s)
            item.candidate = match;
            item.status = ImportMatchStatus.exactMatch;
          } else if (candidatesPool.isNotEmpty) {
            // 🟡 Disputed: found alternatives or time discrepancy
            item.candidate = candidatesPool.first;
            item.alternativeCandidates = candidatesPool.take(5).toList();
            item.status = ImportMatchStatus.disputed;
          } else {
            // 🔴 Not found across all 3 attempts
            item.status = ImportMatchStatus.notFound;
          }
        } catch (_) {
          item.status = ImportMatchStatus.notFound;
        }

        if (!controller.isClosed) {
          controller.add(
            ImportScanProgress(
              processed: i + 1,
              total: total,
              currentQuery: displayQuery,
              exactCount: exactCount,
              disputedCount: disputedCount,
              notFoundCount: notFoundCount,
            ),
          );
        }

        // Small delay to keep UI buttery smooth and animated
        await Future.delayed(const Duration(milliseconds: 70));
      }

      _isScanning = false;
      if (!controller.isClosed) {
        controller.close();
      }
    });

    return controller.stream;
  }

  /// Resolves a disputed track by assigning the user-chosen candidate.
  void resolveDispute(String matchId, ScrapedTrack chosenTrack) {
    for (final item in _stagedMatches) {
      if (item.id == matchId) {
        item.candidate = chosenTrack;
        item.status = ImportMatchStatus.exactMatch;
        break;
      }
    }
  }

  /// Generates a missing tracks text report.
  String generateMissingTracksReport() {
    final missing =
        _stagedMatches.where((m) => m.status == ImportMatchStatus.notFound);
    final sb = StringBuffer();
    sb.writeln('# NCMUS MISSING TRACKS EXPORT');
    sb.writeln('# Total missing: ${missing.length}');
    sb.writeln('');
    for (final m in missing) {
      sb.writeln('${m.originalArtist} - ${m.originalTitle}');
    }
    return sb.toString();
  }

  /// Commits all verified and matched tracks into SQLite and wipes staging session.
  Future<int> commitToLibrary({required String playlistName}) async {
    final toImport = _stagedMatches
        .where((m) =>
            m.candidate != null &&
            m.candidate!.streamUrl.isNotEmpty &&
            (m.candidate!.duration > Duration.zero ||
                (m.originalDuration != null &&
                    m.originalDuration! > Duration.zero)))
        .toList();
    if (toImport.isEmpty) {
      await wipeStagingSession();
      return 0;
    }

    final db = await _dbService.database;
    final playlistId = 'pl_${DateTime.now().millisecondsSinceEpoch}';

    await db.insert(
      'playlists',
      {
        'id': playlistId,
        'title': playlistName.trim().isNotEmpty
            ? playlistName.trim()
            : 'Импортированный плейлист',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    int count = 0;
    await db.transaction((txn) async {
      for (final match in toImport) {
        final track = match.candidate;
        final streamUrl = track?.streamUrl ?? '';
        final duration = (track != null && track.duration > Duration.zero)
            ? track.duration
            : (match.originalDuration ?? Duration.zero);

        if (streamUrl.isEmpty || duration <= Duration.zero) continue;

        final trackId = 'import_${match.deduplicationKey.hashCode.abs()}';
        final title = track?.title ?? match.originalTitle;
        final artist = track?.artist ?? match.originalArtist;
        final coverUrl = track?.coverUrl;
        final source = track?.sourceName ?? 'Import';

        final existing = await txn.query(
          'tracks',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [trackId],
          limit: 1,
        );

        if (existing.isEmpty) {
          final entity = TrackEntity(
            id: trackId,
            title: title,
            artist: artist,
            duration: duration,
            streamUrl: streamUrl,
            localPath: null,
            coverUrl: coverUrl,
            sourceName: source,
            isDownloaded: false,
            isFavorite: true,
            createdAt: DateTime.now(),
          );
          await txn.insert('tracks', entity.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          await txn.update('tracks', {'is_favorite': 1},
              where: 'id = ?', whereArgs: [trackId]);
        }

        await txn.insert(
          'playlist_tracks',
          {'playlist_id': playlistId, 'track_id': trackId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        count++;
      }
    });

    _dbService.notifyLibraryChanged();
    await wipeStagingSession();
    return count;
  }
}
