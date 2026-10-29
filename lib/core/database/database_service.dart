import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:io' show Directory, File;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/storage/models/playlist_entity.dart';
import '../../features/storage/models/track_entity.dart';
import '../../features/sync/models/sync_snapshot.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static final ValueNotifier<int> blacklistCount = ValueNotifier<int>(0);

  Database? _database;
  String? _customPath;

  final StreamController<void> _libraryChanges =
      StreamController<void>.broadcast();

  DatabaseService._internal();

  factory DatabaseService() => instance;

  /// Emits after favourites, downloads or track rows change. UI layers use
  /// this to keep the library in sync without polling.
  Stream<void> get libraryChanges => _libraryChanges.stream;

  void notifyLibraryChanged() {
    if (!_libraryChanges.isClosed) {
      _libraryChanges.add(null);
    }
  }

  static void initFfiIfNeeded() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  void setCustomPath(String? path) {
    _customPath = path;
    _database = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    initFfiIfNeeded();

    final String dbPath;
    if (_customPath != null) {
      dbPath = _customPath!;
    } else {
      final defaultDatabasesPath = await getDatabasesPath();
      dbPath = p.join(defaultDatabasesPath, 'ncmus.db');
    }

    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createSchema,
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS blacklist (
            id TEXT PRIMARY KEY,
            normalized_title TEXT NOT NULL,
            artist TEXT NOT NULL,
            created_at INTEGER NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS listening_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            artwork_url TEXT,
            duration_seconds INTEGER,
            played_at INTEGER NOT NULL
          );
        ''');
        try {
          await db.execute('ALTER TABLE playlists ADD COLUMN description TEXT;');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE playlists ADD COLUMN color TEXT;');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE playlist_tracks ADD COLUMN position INTEGER NOT NULL DEFAULT 0;',
          );
        } catch (_) {}
        final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM blacklist'),
            ) ??
            0;
        blacklistCount.value = count;
      },
    );

    _database = db;

    // Startup cleanup: Purge any ghost tracks with 00:00 duration and no streams
    try {
      await purgeZeroDurationGhostTracks();
    } catch (e) {
      debugPrint('Startup ghost tracks purge: $e');
    }

    return db;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        stream_url TEXT NOT NULL,
        local_path TEXT,
        cover_url TEXT,
        source_name TEXT NOT NULL,
        is_downloaded INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        color TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE playlist_tracks (
        playlist_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, track_id)
      );
    ''');

    await db.execute('''
      CREATE TABLE sync_outbox (
        id TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS blacklist (
        id TEXT PRIMARY KEY,
        normalized_title TEXT NOT NULL,
        artist TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS listening_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        artwork_url TEXT,
        duration_seconds INTEGER,
        played_at INTEGER NOT NULL
      );
    ''');
  }

  Future<void> insertOrUpdateTrack(TrackEntity track) async {
    final db = await database;
    await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyLibraryChanged();
  }

  Future<TrackEntity?> getTrack(String id) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return TrackEntity.fromMap(results.first);
    }
    return null;
  }

  Future<List<TrackEntity>> getAllDownloadedTracks() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'is_downloaded = 1',
      orderBy: 'created_at DESC',
    );

    return results.map((map) => TrackEntity.fromMap(map)).toList();
  }

  Future<void> markAsDownloaded(String id, String localPath) async {
    final db = await database;
    await db.update(
      'tracks',
      {
        'is_downloaded': 1,
        'local_path': localPath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyLibraryChanged();
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    final db = await database;
    await db.update(
      'tracks',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await addOutboxAction(
        'toggle_favorite', {'id': id, 'is_favorite': isFavorite});
    notifyLibraryChanged();
  }

  Future<List<TrackEntity>> getFavoriteTracks() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'is_favorite = 1',
      orderBy: 'created_at DESC',
    );
    return results.map((map) => TrackEntity.fromMap(map)).toList();
  }

  Future<void> deleteTrack(String id) async {
    final db = await database;
    await db.delete('tracks', where: 'id = ?', whereArgs: [id]);
    await addOutboxAction('delete_track', {'id': id});
    notifyLibraryChanged();
  }

  Future<void> removeDownload(String id) async {
    final db = await database;
    await db.update(
      'tracks',
      {
        'is_downloaded': 0,
        'local_path': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyLibraryChanged();
  }

  Future<List<TrackEntity>> getAllTracks() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      orderBy: 'created_at DESC',
    );
    return results.map((map) => TrackEntity.fromMap(map)).toList();
  }

  Future<int> getLocalDbVersion() async {
    final val = await getSyncMeta('db_version');
    if (val != null) {
      return int.tryParse(val) ?? 0;
    }
    return 0;
  }

  Future<void> setLocalDbVersion(int version) async {
    await setSyncMeta('db_version', version.toString());
  }

  Future<String?> getSyncMeta(String key) async {
    final db = await database;
    final results = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<void> setSyncMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addOutboxAction(
      String action, Map<String, dynamic> payload) async {
    final db = await database;
    final id = '${DateTime.now().microsecondsSinceEpoch}_$action';
    await db.insert(
      'sync_outbox',
      {
        'id': id,
        'action': action,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getOutboxEntries() async {
    final db = await database;
    return await db.query('sync_outbox', orderBy: 'created_at ASC');
  }

  Future<void> clearOutbox() async {
    final db = await database;
    await db.delete('sync_outbox');
  }

  Future<void> mergeRemoteSnapshot(SyncSnapshot snapshot) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final rawTrack in snapshot.tracks) {
        final id = rawTrack['id'] as String?;
        if (id == null || id.isEmpty) continue;

        final existing = await txn.query(
          'tracks',
          columns: ['id', 'is_downloaded', 'local_path'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        final title = (rawTrack['title'] as String?) ?? 'Unknown Title';
        final artist = (rawTrack['artist'] as String?) ?? 'Unknown Artist';
        final durationMs = (rawTrack['duration_ms'] as num?)?.toInt() ?? 0;
        final streamUrl = (rawTrack['stream_url'] as String?) ?? '';
        final coverUrl = rawTrack['cover_url'] as String?;
        final sourceName = (rawTrack['source_name'] as String?) ?? 'Unknown';
        final isFavorite =
            (rawTrack['is_favorite'] == 1 || rawTrack['is_favorite'] == true)
                ? 1
                : 0;
        final createdAt = (rawTrack['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;

        if (existing.isNotEmpty) {
          // Merge Rule: preserve local fields `is_downloaded` and `local_path`!
          await txn.update(
            'tracks',
            {
              'title': title,
              'artist': artist,
              'duration_ms': durationMs,
              'stream_url': streamUrl,
              'cover_url': coverUrl,
              'source_name': sourceName,
              'is_favorite': isFavorite,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          // Brand new track from remote
          await txn.insert('tracks', {
            'id': id,
            'title': title,
            'artist': artist,
            'duration_ms': durationMs,
            'stream_url': streamUrl,
            'local_path': null,
            'cover_url': coverUrl,
            'source_name': sourceName,
            'is_downloaded': 0,
            'is_favorite': isFavorite,
            'created_at': createdAt,
          });
        }
      }

      for (final rawEntry in snapshot.blacklist) {
        final entry = rawEntry.trim();
        if (entry.isEmpty) continue;

        final String normTitle;
        final String artist;
        final pipeIndex = entry.indexOf('|');
        if (pipeIndex != -1) {
          normTitle = entry.substring(0, pipeIndex).trim();
          artist = entry.substring(pipeIndex + 1).trim();
        } else {
          normTitle = normalizeTitle(entry);
          artist = '';
        }

        if (normTitle.isEmpty && artist.isEmpty) continue;

        final existing = await txn.query(
          'blacklist',
          columns: ['id'],
          where: 'normalized_title = ? AND artist = ?',
          whereArgs: [normTitle, artist],
          limit: 1,
        );

        if (existing.isEmpty) {
          final id =
              '${DateTime.now().microsecondsSinceEpoch}_${normTitle.hashCode.abs()}_${artist.hashCode.abs()}';
          await txn.insert(
            'blacklist',
            {
              'id': id,
              'normalized_title': normTitle,
              'artist': artist,
              'created_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      for (final rawPl in snapshot.playlists) {
        final id = rawPl['id'] as String?;
        final title =
            (rawPl['title'] as String?)?.trim() ?? 'Безымянный плейлист';
        if (title.isEmpty) continue;

        final desc = rawPl['description'] as String?;
        final color = rawPl['color'] as String?;
        final createdAt = (rawPl['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;

        List<Map<String, dynamic>> existingPl = [];
        if (id != null && id.isNotEmpty) {
          existingPl = await txn.query(
            'playlists',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
        }
        if (existingPl.isEmpty) {
          existingPl = await txn.query(
            'playlists',
            where: 'title = ?',
            whereArgs: [title],
            limit: 1,
          );
        }

        final targetId = existingPl.isNotEmpty
            ? existingPl.first['id'] as String
            : (id != null && id.isNotEmpty
                ? id
                : '${DateTime.now().microsecondsSinceEpoch}_${title.hashCode.abs()}');

        if (existingPl.isNotEmpty) {
          await txn.update(
            'playlists',
            {
              'title': title,
              if (desc != null) 'description': desc,
              if (color != null) 'color': color,
            },
            where: 'id = ?',
            whereArgs: [targetId],
          );
        } else {
          await txn.insert(
            'playlists',
            {
              'id': targetId,
              'title': title,
              'description': desc,
              'color': color,
              'created_at': createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        final trackIds = <String>[];
        if (rawPl['track_ids'] is List) {
          for (final tid in rawPl['track_ids'] as List) {
            if (tid != null && tid.toString().isNotEmpty) {
              trackIds.add(tid.toString());
            }
          }
        } else if (rawPl['tracks'] is List) {
          for (final t in rawPl['tracks'] as List) {
            if (t is Map && t['id'] != null) {
              trackIds.add(t['id'].toString());
            } else if (t is String && t.isNotEmpty) {
              trackIds.add(t);
            }
          }
        }

        for (int i = 0; i < trackIds.length; i++) {
          final tId = trackIds[i];
          final existingLink = await txn.query(
            'playlist_tracks',
            where: 'playlist_id = ? AND track_id = ?',
            whereArgs: [targetId, tId],
            limit: 1,
          );
          if (existingLink.isEmpty) {
            await txn.insert(
              'playlist_tracks',
              {
                'playlist_id': targetId,
                'track_id': tId,
                'position': i,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }

      await txn.insert(
        'sync_meta',
        {'key': 'db_version', 'value': snapshot.version.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    final freshCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM blacklist'),
        ) ??
        0;
    blacklistCount.value = freshCount;

    notifyLibraryChanged();
  }

  // ---------------------------------------------------------------------------
  // Blacklist
  // ---------------------------------------------------------------------------

  static String normalizeTitle(String title) {
    if (title.isEmpty) return '';
    var cleaned = title.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{<].*?[\)\]\}>]'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(feat|ft|prod)\b.*$', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(remix|edit|slowed|reverb|boosted|bass boosted|acoustic|live|instrumental|version|cover|vip|sped up|speed up)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    cleaned =
        cleaned.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? title.toLowerCase().trim() : cleaned;
  }

  Future<void> addToBlacklist(String title, String artist) async {
    final db = await database;
    final normTitle = normalizeTitle(title);
    final cleanArtist = artist.trim();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${normTitle.hashCode.abs()}';
    await db.insert(
      'blacklist',
      {
        'id': id,
        'normalized_title': normTitle,
        'artist': cleanArtist,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    blacklistCount.value++;
    await addOutboxAction('blacklist_add', {
      'title': title,
      'artist': cleanArtist,
      'normalized': normTitle,
    });
  }

  Future<bool> isBlacklisted(String title, String artist) async {
    final db = await database;
    final normTitle = normalizeTitle(title);
    final results = await db.query(
      'blacklist',
      where: 'normalized_title = ?',
      whereArgs: [normTitle],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<bool> isTrackBlacklisted(String title, String artist) async {
    final db = await database;
    final normTitle = normalizeTitle(title);
    if (normTitle.isEmpty) return false;
    final cleanArtist = artist.trim();
    if (cleanArtist.isNotEmpty) {
      final results = await db.query(
        'blacklist',
        where:
            'normalized_title = ? AND (artist = ? OR artist = ? OR artist = ?)',
        whereArgs: [normTitle, cleanArtist, '', 'Unknown Artist'],
        limit: 1,
      );
      if (results.isNotEmpty) return true;
    }
    final results = await db.query(
      'blacklist',
      where: 'normalized_title = ?',
      whereArgs: [normTitle],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<void> removeFromBlacklist(String title, String artist) async {
    final db = await database;
    final normTitle = normalizeTitle(title);
    final cleanArtist = artist.trim();
    int deleted = 0;
    if (cleanArtist.isNotEmpty) {
      deleted = await db.delete(
        'blacklist',
        where: 'normalized_title = ? AND (artist = ? OR artist = ?)',
        whereArgs: [normTitle, cleanArtist, ''],
      );
    }
    if (deleted == 0) {
      deleted = await db.delete(
        'blacklist',
        where: 'normalized_title = ?',
        whereArgs: [normTitle],
      );
    }
    final freshCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM blacklist'),
        ) ??
        0;
    blacklistCount.value = freshCount;
    await addOutboxAction('blacklist_remove', {
      'title': title,
      'artist': cleanArtist,
      'normalized': normTitle,
    });
    notifyLibraryChanged();
  }

  // ---------------------------------------------------------------------------
  // Listening History & Statistics
  // ---------------------------------------------------------------------------

  Future<void> logPlayHistory(MediaItem item) async {
    final db = await database;
    final title = item.title.trim();
    final artist = (item.artist ?? 'Unknown Artist').trim();
    final artworkUrl = item.artUri?.toString();
    final durationSeconds = item.duration?.inSeconds ?? 0;
    final playedAt = DateTime.now().millisecondsSinceEpoch;

    await db.insert('listening_history', {
      'title': title,
      'artist': artist,
      'artwork_url': artworkUrl,
      'duration_seconds': durationSeconds,
      'played_at': playedAt,
    });
    notifyLibraryChanged();
  }

  Future<List<Map<String, dynamic>>> getListeningHistory(
      {int limit = 50}) async {
    final db = await database;
    return await db.query(
      'listening_history',
      orderBy: 'played_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getTopArtists({int limit = 5}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT artist, COUNT(*) as play_count, MAX(played_at) as last_played, MAX(artwork_url) as artwork_url
      FROM listening_history
      WHERE TRIM(artist) != ''
      GROUP BY LOWER(artist)
      ORDER BY play_count DESC, last_played DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getTopArtistsWithTracks({int limit = 10}) async {
    final db = await database;
    final artistsRaw = await db.rawQuery('''
      SELECT artist, artwork_url, COUNT(*) as total_plays
      FROM listening_history
      WHERE TRIM(artist) != ''
      GROUP BY artist
      ORDER BY total_plays DESC
      LIMIT ?
    ''', [limit]);

    final result = <Map<String, dynamic>>[];
    for (final a in artistsRaw) {
      final artistName = a['artist'] as String;
      final topTracks = await db.rawQuery('''
        SELECT title, artwork_url, duration_seconds, COUNT(*) as track_plays
        FROM listening_history
        WHERE artist = ?
        GROUP BY title
        ORDER BY track_plays DESC
        LIMIT 3
      ''', [artistName]);

      result.add({
        'artist': artistName,
        'artwork_url': a['artwork_url'],
        'total_plays': a['total_plays'],
        'top_tracks': topTracks,
      });
    }
    return result;
  }

  Future<Set<String>> getAllBlacklistedNormalized() async {
    final db = await database;
    final results = await db.query('blacklist', columns: ['normalized_title']);
    return results
        .map((r) => (r['normalized_title'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> getBlacklistedNormalizedTitles() =>
      getAllBlacklistedNormalized();

  Future<List<String>> getBlacklistRaw() async {
    final db = await database;
    final results = await db.query(
      'blacklist',
      columns: ['normalized_title', 'artist'],
      orderBy: 'created_at ASC',
    );
    return results
        .map((r) {
          final normTitle = (r['normalized_title'] as String? ?? '').trim();
          final artist = (r['artist'] as String? ?? '').trim();
          return '$normTitle|$artist';
        })
        .where((s) => s != '|' && s.isNotEmpty)
        .toList();
  }

  Future<void> clearBlacklist() async {
    final db = await database;
    await db.delete('blacklist');
    blacklistCount.value = 0;
    await setSyncMeta('wave_blacklist', '[]');
  }

  Future<int> getBlacklistCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM blacklist'),
        ) ??
        0;
    blacklistCount.value = count;
    return count;
  }

  // ---------------------------------------------------------------------------
  // Ghost Tracks Cleanup
  // ---------------------------------------------------------------------------

  /// Safely purges ghost tracks that have 0 or null duration, no downloaded
  /// local file, and no stream.
  Future<int> purgeZeroDurationGhostTracks() async {
    final db = await database;
    final purgedCount = await db.transaction((txn) async {
      // Find IDs of ghost tracks that:
      // 1) Duration is <= 0 or NULL
      // 2) Have no local file (is_downloaded = 0 and local_path is null or empty)
      final ghostRows = await txn.query(
        'tracks',
        columns: ['id'],
        where:
            "(duration_ms <= 0 OR duration_ms IS NULL) AND (local_path IS NULL OR local_path = '') AND is_downloaded = 0",
      );
      final ghostIds = ghostRows.map((e) => e['id'] as String).toList();

      if (ghostIds.isEmpty) return 0;

      // Delete links from playlists and tracks
      for (final id in ghostIds) {
        await txn
            .delete('playlist_tracks', where: 'track_id = ?', whereArgs: [id]);
        await txn.delete('tracks', where: 'id = ?', whereArgs: [id]);
      }

      return ghostIds.length;
    });

    if (purgedCount > 0) {
      notifyLibraryChanged();
    }
    return purgedCount;
  }

  // ---------------------------------------------------------------------------
  // Playlists CRUD
  // ---------------------------------------------------------------------------

  Future<PlaylistEntity> createPlaylist(
    String title, {
    String? id,
    String? description,
    String? color,
  }) async {
    final db = await database;
    final cleanTitle = title.trim();
    final effectiveId = id ??
        'pl_${DateTime.now().microsecondsSinceEpoch}_${cleanTitle.hashCode.abs()}';
    final now = DateTime.now();

    final entity = PlaylistEntity(
      id: effectiveId,
      title: cleanTitle.isEmpty ? 'Новый плейлист' : cleanTitle,
      description: description?.trim(),
      color: color,
      createdAt: now,
    );

    await db.insert(
      'playlists',
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await addOutboxAction('create_playlist', entity.toMap());
    notifyLibraryChanged();
    return entity;
  }

  Future<void> updatePlaylist(
    String id, {
    String? title,
    String? description,
    String? color,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title.trim();
    if (description != null) updates['description'] = description.trim();
    if (color != null) updates['color'] = color;

    if (updates.isNotEmpty) {
      await db.update(
        'playlists',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
      await addOutboxAction('update_playlist', {'id': id, ...updates});
      notifyLibraryChanged();
    }
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'playlists',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await addOutboxAction('delete_playlist', {'id': id});
    notifyLibraryChanged();
  }

  Future<List<PlaylistEntity>> getPlaylists() async {
    final db = await database;
    final rawPlaylists = await db.query(
      'playlists',
      orderBy: 'created_at DESC',
    );

    final result = <PlaylistEntity>[];
    for (final map in rawPlaylists) {
      final playlistId = map['id'] as String;

      final tracks = await getPlaylistTracks(playlistId);
      final trackCount = tracks.length;
      var totalMs = 0;
      final covers = <String>[];

      for (final t in tracks) {
        totalMs += t.duration.inMilliseconds;
        if (covers.length < 4 && t.coverUrl != null && t.coverUrl!.isNotEmpty) {
          covers.add(t.coverUrl!);
        }
      }

      result.add(
        PlaylistEntity.fromMap(
          map,
          trackCount: trackCount,
          totalDuration: Duration(milliseconds: totalMs),
          coverUrls: covers,
        ),
      );
    }
    return result;
  }

  Future<PlaylistEntity?> getPlaylist(String id) async {
    final db = await database;
    final raw = await db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (raw.isEmpty) return null;

    final tracks = await getPlaylistTracks(id);
    final covers = <String>[];
    var totalMs = 0;
    for (final t in tracks) {
      totalMs += t.duration.inMilliseconds;
      if (covers.length < 4 && t.coverUrl != null && t.coverUrl!.isNotEmpty) {
        covers.add(t.coverUrl!);
      }
    }

    return PlaylistEntity.fromMap(
      raw.first,
      trackCount: tracks.length,
      totalDuration: Duration(milliseconds: totalMs),
      coverUrls: covers,
    );
  }

  Future<void> addTrackToPlaylist(String playlistId, TrackEntity track) async {
    final db = await database;
    // 1. Ensure track is recorded in tracks table
    await insertOrUpdateTrack(track);

    // 2. Find max position
    final posResult = await db.rawQuery(
      'SELECT MAX(position) as max_pos FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final maxPos = (posResult.isNotEmpty && posResult.first['max_pos'] != null)
        ? (posResult.first['max_pos'] as num).toInt()
        : -1;
    final newPos = maxPos + 1;

    // 3. Insert link
    await db.insert(
      'playlist_tracks',
      {
        'playlist_id': playlistId,
        'track_id': track.id,
        'position': newPos,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await addOutboxAction('add_playlist_track', {
      'playlist_id': playlistId,
      'track_id': track.id,
      'position': newPos,
    });
    notifyLibraryChanged();
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    final db = await database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
    await addOutboxAction('remove_playlist_track', {
      'playlist_id': playlistId,
      'track_id': trackId,
    });
    notifyLibraryChanged();
  }

  Future<List<TrackEntity>> getPlaylistTracks(String playlistId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT t.* FROM tracks t
      INNER JOIN playlist_tracks pt ON t.id = pt.track_id
      WHERE pt.playlist_id = ?
      ORDER BY pt.position ASC, pt.rowid ASC
    ''', [playlistId]);

    return results.map((map) => TrackEntity.fromMap(map)).toList();
  }

  Future<void> reorderPlaylistTracks(
    String playlistId,
    List<String> orderedTrackIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedTrackIds.length; i++) {
        await txn.update(
          'playlist_tracks',
          {'position': i},
          where: 'playlist_id = ? AND track_id = ?',
          whereArgs: [playlistId, orderedTrackIds[i]],
        );
      }
    });
    await addOutboxAction('reorder_playlist_tracks', {
      'playlist_id': playlistId,
      'track_ids': orderedTrackIds,
    });
    notifyLibraryChanged();
  }

  Future<Set<String>> getPlaylistsForTrack(String trackId) async {
    final db = await database;
    final rows = await db.query(
      'playlist_tracks',
      columns: ['playlist_id'],
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
    return rows.map((r) => r['playlist_id'] as String).toSet();
  }

  Future<List<Map<String, dynamic>>> getPlaylistsForSync() async {
    final playlists = await getPlaylists();
    final list = <Map<String, dynamic>>[];
    for (final p in playlists) {
      final tracks = await getPlaylistTracks(p.id);
      list.add({
        'id': p.id,
        'title': p.title,
        'description': p.description,
        'color': p.color,
        'created_at': p.createdAt.millisecondsSinceEpoch,
        'track_ids': tracks.map((t) => t.id).toList(),
      });
    }
    return list;
  }

  Future<List<TrackEntity>> getAllPlayableOfflineTracks() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: "(local_path IS NOT NULL AND local_path != '')",
      orderBy: 'created_at DESC',
    );
    final list = <TrackEntity>[];
    for (final map in results) {
      final track = TrackEntity.fromMap(map);
      if (track.localPath != null && track.localPath!.isNotEmpty) {
        final f = File(track.localPath!);
        if (f.existsSync() && f.lengthSync() > 0) {
          list.add(track);
        }
      }
    }
    return list;
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
