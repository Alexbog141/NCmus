import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';
import 'package:ncmus/features/sync/models/sync_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService dbService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_playlist_test_');
    dbService = DatabaseService.instance;
    dbService.setCustomPath(p.join(tempDir.path, 'test_playlist.db'));
  });

  tearDown(() async {
    await dbService.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Playlist CRUD & Management Tests', () {
    test('1. Create, Read, Update, and Delete playlist', () async {
      // Create playlist
      final playlist = await dbService.createPlaylist(
        'Cyberpunk 2077 Night Mix',
        description: 'Atmospheric neon electronics',
        color: '#00F0FF',
      );

      expect(playlist.title, equals('Cyberpunk 2077 Night Mix'));
      expect(playlist.description, equals('Atmospheric neon electronics'));
      expect(playlist.color, equals('#00F0FF'));

      // Read playlist
      final fetched = await dbService.getPlaylist(playlist.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, equals(playlist.id));
      expect(fetched.title, equals('Cyberpunk 2077 Night Mix'));
      expect(fetched.description, equals('Atmospheric neon electronics'));
      expect(fetched.color, equals('#00F0FF'));

      final allPlaylists = await dbService.getPlaylists();
      expect(allPlaylists.any((p) => p.id == playlist.id), isTrue);

      // Update / Rename playlist
      await dbService.updatePlaylist(
        playlist.id,
        title: 'Cyberpunk 2077 Night Mix [Updated]',
        description: 'New Description',
        color: '#FF007F',
      );

      final updated = await dbService.getPlaylist(playlist.id);
      expect(updated, isNotNull);
      expect(updated!.title, equals('Cyberpunk 2077 Night Mix [Updated]'));
      expect(updated.description, equals('New Description'));
      expect(updated.color, equals('#FF007F'));

      // Delete playlist
      await dbService.deletePlaylist(playlist.id);
      final deleted = await dbService.getPlaylist(playlist.id);
      expect(deleted, isNull);

      final playlistsAfterDelete = await dbService.getPlaylists();
      expect(playlistsAfterDelete.any((p) => p.id == playlist.id), isFalse);
    });

    test('2. Add tracks, reorder, and remove tracks from playlist', () async {
      final playlist = await dbService.createPlaylist(
        'Synth Classics',
        description: 'Best retro beats',
      );

      final track1 = TrackEntity(
        id: 'track-1',
        title: 'Resonance',
        artist: 'HOME',
        duration: const Duration(minutes: 3, seconds: 32),
        streamUrl: 'https://example.com/resonance.mp3',
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );

      final track2 = TrackEntity(
        id: 'track-2',
        title: 'Dust',
        artist: 'M|O|O|N',
        duration: const Duration(minutes: 5, seconds: 2),
        streamUrl: 'https://example.com/dust.mp3',
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );

      final track3 = TrackEntity(
        id: 'track-3',
        title: 'Nightcall',
        artist: 'Kavinsky',
        duration: const Duration(minutes: 4, seconds: 19),
        streamUrl: 'https://example.com/nightcall.mp3',
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );

      // Add tracks
      await dbService.addTrackToPlaylist(playlist.id, track1);
      await dbService.addTrackToPlaylist(playlist.id, track2);
      await dbService.addTrackToPlaylist(playlist.id, track3);

      var tracks = await dbService.getPlaylistTracks(playlist.id);
      expect(tracks.length, equals(3));
      expect(tracks[0].id, equals('track-1'));
      expect(tracks[1].id, equals('track-2'));
      expect(tracks[2].id, equals('track-3'));

      // Check track containment lookup
      final plSet1 = await dbService.getPlaylistsForTrack('track-1');
      expect(plSet1.contains(playlist.id), isTrue);

      // Reorder tracks: put track-3 first: [track-3, track-1, track-2]
      await dbService.reorderPlaylistTracks(
        playlist.id,
        ['track-3', 'track-1', 'track-2'],
      );

      tracks = await dbService.getPlaylistTracks(playlist.id);
      expect(tracks.length, equals(3));
      expect(tracks[0].id, equals('track-3'));
      expect(tracks[1].id, equals('track-1'));
      expect(tracks[2].id, equals('track-2'));

      // Remove track-1
      await dbService.removeTrackFromPlaylist(playlist.id, 'track-1');
      tracks = await dbService.getPlaylistTracks(playlist.id);
      expect(tracks.length, equals(2));
      expect(tracks.any((t) => t.id == 'track-1'), isFalse);

      final plSetAfter = await dbService.getPlaylistsForTrack('track-1');
      expect(plSetAfter.contains(playlist.id), isFalse);
    });

    test('3. getPlaylistsForSync exports playlist structure', () async {
      final playlist = await dbService.createPlaylist(
        'Workout Phonk',
        description: 'High energy',
        color: '#00FF66',
      );

      final track = TrackEntity(
        id: 'track-phonk-1',
        title: 'Metamorphosis',
        artist: 'INTERWORLD',
        duration: const Duration(minutes: 2, seconds: 22),
        streamUrl: 'https://example.com/meta.mp3',
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );
      await dbService.addTrackToPlaylist(playlist.id, track);

      final syncPlaylists = await dbService.getPlaylistsForSync();
      expect(syncPlaylists.length, equals(1));
      final export = syncPlaylists.first;
      expect(export['id'], equals(playlist.id));
      expect(export['title'], equals('Workout Phonk'));
      expect(export['description'], equals('High energy'));
      expect(export['color'], equals('#00FF66'));
      expect(export['track_ids'], equals(['track-phonk-1']));
    });

    test('4. mergeRemoteSnapshot merges remote playlists without duplicate creation',
        () async {
      // 1. Initial local playlist
      final localPl = await dbService.createPlaylist(
        'Existing Mix',
        id: 'pl-remote-100',
        description: 'Local desc',
        color: '#00F0FF',
      );

      // 2. Prepare remote snapshot with the same playlist (updated title) plus a new one
      final snapshot = SyncSnapshot(
        version: 10,
        tracks: [
          {
            'id': 'rem-track-1',
            'title': 'Remote Track 1',
            'artist': 'Artist A',
            'duration_ms': 180000,
            'stream_url': 'https://remote.com/1.mp3',
            'source_name': 'Muzofond',
            'is_favorite': 1,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          {
            'id': 'rem-track-2',
            'title': 'Remote Track 2',
            'artist': 'Artist B',
            'duration_ms': 200000,
            'stream_url': 'https://remote.com/2.mp3',
            'source_name': 'Hitmo',
            'is_favorite': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
        ],
        playlists: [
          {
            'id': 'pl-remote-100',
            'title': 'Existing Mix [Merged from Remote]',
            'description': 'Updated remote desc',
            'color': '#B026FF',
            'track_ids': ['rem-track-1'],
          },
          {
            'id': 'pl-remote-200',
            'title': 'Brand New Remote Playlist',
            'description': 'Fresh import',
            'color': '#FF007F',
            'track_ids': ['rem-track-2'],
          },
        ],
      );

      // Merge
      await dbService.mergeRemoteSnapshot(snapshot);

      final playlists = await dbService.getPlaylists();
      expect(playlists.length, equals(2));

      // pl-remote-100 was merged without creating a duplicate
      final existingMerged = await dbService.getPlaylist(localPl.id);
      expect(existingMerged, isNotNull);
      expect(existingMerged!.title, equals('Existing Mix [Merged from Remote]'));
      expect(existingMerged.description, equals('Updated remote desc'));
      expect(existingMerged.color, equals('#B026FF'));

      final tracks100 = await dbService.getPlaylistTracks('pl-remote-100');
      expect(tracks100.length, equals(1));
      expect(tracks100.first.id, equals('rem-track-1'));

      // pl-remote-200 was inserted as a new playlist
      final newPl = await dbService.getPlaylist('pl-remote-200');
      expect(newPl, isNotNull);
      expect(newPl!.title, equals('Brand New Remote Playlist'));

      final tracks200 = await dbService.getPlaylistTracks('pl-remote-200');
      expect(tracks200.length, equals(1));
      expect(tracks200.first.id, equals('rem-track-2'));

      // Merging a second time should be idempotent (no duplicates created)
      await dbService.mergeRemoteSnapshot(snapshot);
      final playlistsSecondMerge = await dbService.getPlaylists();
      expect(playlistsSecondMerge.length, equals(2));
    });
  });
}
