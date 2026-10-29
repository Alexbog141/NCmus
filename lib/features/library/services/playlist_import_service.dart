import 'dart:async';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../storage/models/track_entity.dart';

class ImportedTrackItem {
  final String artist;
  final String title;

  const ImportedTrackItem({
    required this.artist,
    required this.title,
  });

  String get key =>
      '${artist.toLowerCase().trim()}|${title.toLowerCase().trim()}';
}

/// Service that parses and imports music playlists from VK, Yandex Music,
/// and plain text files into the local NCmus SQLite library.
class PlaylistImportService {
  static final PlaylistImportService instance =
      PlaylistImportService._internal();

  final DatabaseService _dbService;

  PlaylistImportService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  PlaylistImportService._internal() : _dbService = DatabaseService.instance;

  factory PlaylistImportService.getInstance() => instance;

  /// Parses raw text into a list of cleaned, deduplicated track items.
  List<ImportedTrackItem> parseRawText(String rawText) {
    if (rawText.trim().isEmpty) return const [];

    final lines = rawText.split(RegExp(r'[\r\n]+'));
    final uniqueItems = <String, ImportedTrackItem>{};

    for (var rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;

      // 1. Strip URLs
      line = line.replaceAll(RegExp(r'https?:\/\/\S+'), '').trim();
      if (line.isEmpty) continue;

      // 2. Strip leading track numbers: "1. ", "01) ", "[1] ", "#1 "
      line = line.replaceAll(RegExp(r'^[#\[\(]?\d+[\.\)\]]?\s*'), '').trim();

      // 3. Strip leading or trailing durations: "03:45", "[3:20]", "(4:15)"
      line =
          line.replaceAll(RegExp(r'[\(\[]?\d{1,2}:\d{2}[\)\]]?$'), '').trim();
      line =
          line.replaceAll(RegExp(r'^[\(\[]?\d{1,2}:\d{2}[\)\]]?'), '').trim();

      String artist = '';
      String title = '';

      // 4. Check Tab delimiter (common in Yandex Music clipboard copy)
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
      }
      // 5. Check Dash delimiters: em-dash "—", en-dash "–", hyphen "-"
      else if (line.contains(' — ') ||
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
        // Fallback: single name
        title = line;
        artist = 'Unknown Artist';
      }

      // Cleanup remaining artifacts
      artist = artist.replaceAll(RegExp(r'^["«\x27]|["»\x27]$'), '').trim();
      title = title.replaceAll(RegExp(r'^["«\x27]|["»\x27]$'), '').trim();

      if (title.isEmpty) continue;
      if (artist.isEmpty) artist = 'Unknown Artist';

      final item = ImportedTrackItem(artist: artist, title: title);
      uniqueItems[item.key] = item;
    }

    return uniqueItems.values.toList();
  }

  /// Imports parsed tracks into SQLite:
  /// - Creates a playlist entry.
  /// - Adds tracks to `tracks` table with `is_favorite = 1, is_downloaded = 0`.
  /// - Links them in `playlist_tracks`.
  /// - Reports continuous progress via [onProgress].
  Future<int> importTracksFromText(
    String rawText, {
    String playlistName = 'Импортированные',
    void Function(int processed, int total)? onProgress,
  }) async {
    final parsed = parseRawText(rawText);
    if (parsed.isEmpty) return 0;

    final db = await _dbService.database;
    final playlistId = 'import_pl_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Create Playlist
    await db.insert(
      'playlists',
      {
        'id': playlistId,
        'title': playlistName.trim().isNotEmpty
            ? playlistName.trim()
            : 'Импортированные',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    var count = 0;
    final total = parsed.length;

    await db.transaction((txn) async {
      for (var i = 0; i < total; i++) {
        final item = parsed[i];
        final trackId = 'import_${item.key.hashCode.abs()}';

        // Check if track already exists
        final existing = await txn.query(
          'tracks',
          columns: ['id', 'is_favorite', 'is_downloaded', 'local_path'],
          where: 'id = ?',
          whereArgs: [trackId],
          limit: 1,
        );

        if (existing.isEmpty) {
          final newEntity = TrackEntity(
            id: trackId,
            title: item.title,
            artist: item.artist,
            duration: Duration.zero,
            streamUrl: '',
            localPath: null,
            coverUrl: null,
            sourceName: 'Import',
            isDownloaded: false,
            isFavorite: true,
            createdAt: DateTime.now(),
          );
          await txn.insert(
            'tracks',
            newEntity.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          // If already in library, mark as favorite
          await txn.update(
            'tracks',
            {'is_favorite': 1},
            where: 'id = ?',
            whereArgs: [trackId],
          );
        }

        // Link to playlist
        await txn.insert(
          'playlist_tracks',
          {
            'playlist_id': playlistId,
            'track_id': trackId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        count++;
        onProgress?.call(count, total);
      }
    });

    _dbService.notifyLibraryChanged();
    return count;
  }
}
