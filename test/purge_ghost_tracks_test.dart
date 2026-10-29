import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService Ghost Tracks Purge Tests', () {
    late DatabaseService dbService;

    setUp(() async {
      dbService = DatabaseService();
      dbService.setCustomPath(inMemoryDatabasePath);
      await dbService.database;
    });

    tearDown(() async {
      await dbService.close();
    });

    test('purgeZeroDurationGhostTracks deletes ghost tracks and preserves valid ones', () async {
      final db = await dbService.database;

      // 1. Insert a ghost track (duration = 0, no local_path, is_downloaded = 0)
      final ghost1 = TrackEntity(
        id: 'ghost_1',
        title: 'Ghost Track 1',
        artist: 'Unknown',
        duration: Duration.zero,
        streamUrl: '',
        sourceName: 'vk',
        isDownloaded: false,
        createdAt: DateTime.now(),
      );
      await db.insert('tracks', ghost1.toMap());

      // 2. Insert another ghost track with negative/zero duration
      final ghost2 = TrackEntity(
        id: 'ghost_2',
        title: 'Ghost Track 2',
        artist: 'Unknown',
        duration: const Duration(seconds: -5),
        streamUrl: 'import_123',
        sourceName: 'vk',
        isDownloaded: false,
        createdAt: DateTime.now(),
      );
      await db.insert('tracks', ghost2.toMap());

      // Insert playlist mapping for ghost track
      await db.insert('playlist_tracks', {
        'playlist_id': 'pl_test',
        'track_id': 'ghost_1',
      });

      // 3. Insert a VALID streaming track (duration > 0)
      final validStream = TrackEntity(
        id: 'valid_stream',
        title: 'Real Song',
        artist: 'Real Artist',
        duration: const Duration(minutes: 3, seconds: 45),
        streamUrl: 'https://example.com/audio.mp3',
        sourceName: 'vk',
        isDownloaded: false,
        createdAt: DateTime.now(),
      );
      await db.insert('tracks', validStream.toMap());

      // 4. Insert a VALID downloaded track (even if duration metadata was 0, it has a local file)
      final validLocal = TrackEntity(
        id: 'valid_local',
        title: 'Local MP3',
        artist: 'Local Artist',
        duration: Duration.zero,
        streamUrl: '',
        sourceName: 'local',
        localPath: 'C:\\Music\\song.mp3',
        isDownloaded: true,
        createdAt: DateTime.now(),
      );
      await db.insert('tracks', validLocal.toMap());

      // Verify all 4 tracks were in DB
      final beforeTracks = await db.query('tracks');
      expect(beforeTracks.length, 4);

      // Run purge
      final purgedCount = await dbService.purgeZeroDurationGhostTracks();
      expect(purgedCount, 2);

      // Check remaining tracks
      final afterTracks = await db.query('tracks');
      expect(afterTracks.length, 2);

      final remainingIds = afterTracks.map((t) => t['id']).toSet();
      expect(remainingIds.contains('valid_stream'), true);
      expect(remainingIds.contains('valid_local'), true);
      expect(remainingIds.contains('ghost_1'), false);
      expect(remainingIds.contains('ghost_2'), false);

      // Check playlist mapping for ghost was deleted
      final playlistTracks = await db.query('playlist_tracks');
      expect(playlistTracks.isEmpty, true);
    });
  });
}
