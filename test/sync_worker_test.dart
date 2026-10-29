import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';
import 'package:ncmus/features/sync/models/sync_snapshot.dart';
import 'package:ncmus/features/sync/services/cloud_sync_service.dart';
import 'package:ncmus/features/sync/workers/sync_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService dbService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_sync_test_');
    dbService = DatabaseService.instance;
    dbService.setCustomPath(p.join(tempDir.path, 'test_sync.db'));
  });

  tearDown(() async {
    await dbService.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('1. Correctness of packing local tracks into SyncSnapshot', () {
    final now = DateTime.now();
    final localTrack = TrackEntity(
      id: 'track-101',
      title: 'Psychosocial',
      artist: 'Slipknot',
      duration: const Duration(minutes: 4, seconds: 44),
      streamUrl: 'https://example.com/audio.mp3',
      localPath: 'C:\\Music\\Slipknot - Psychosocial.mp3',
      coverUrl: 'https://example.com/cover.jpg',
      sourceName: 'Hitmo',
      isDownloaded: true,
      isFavorite: true,
      createdAt: now,
    );

    final snapshot = SyncSnapshot.fromDatabase(
      version: 5,
      tracks: [localTrack],
      theme: 'cyberpunk_neon',
    );

    expect(snapshot.version, equals(5));
    expect(snapshot.theme, equals('cyberpunk_neon'));
    expect(snapshot.tracks.length, equals(1));

    final map = snapshot.tracks.first;
    expect(map['id'], equals('track-101'));
    expect(map['title'], equals('Psychosocial'));
    expect(map['artist'], equals('Slipknot'));
    expect(map['duration_ms'], equals(284000));
    expect(map['stream_url'], equals('https://example.com/audio.mp3'));
    expect(map['cover_url'], equals('https://example.com/cover.jpg'));
    expect(map['source_name'], equals('Hitmo'));
    expect(map['is_favorite'], equals(1));
    expect(map['created_at'], equals(now.millisecondsSinceEpoch));

    // Verify serialization roundtrip
    final jsonMap = snapshot.toJson();
    final restored = SyncSnapshot.fromJson(jsonMap);
    expect(restored.version, equals(5));
    expect(restored.tracks.length, equals(1));
    expect(restored.tracks.first['id'], equals('track-101'));
  });

  test('2. mergeRemoteSnapshot: preserves local_path and is_downloaded = 1', () async {
    // A. Insert an existing downloaded track into local DB
    final existingTrack = TrackEntity(
      id: 'track-local-fav',
      title: 'Old Title',
      artist: 'Old Artist',
      duration: const Duration(minutes: 3),
      streamUrl: 'https://example.com/old.mp3',
      localPath: 'C:\\Music\\NCmus\\LocalFile.mp3',
      coverUrl: null,
      sourceName: 'Hitmo',
      isDownloaded: true,
      isFavorite: false,
      createdAt: DateTime.now(),
    );
    await dbService.insertOrUpdateTrack(existingTrack);

    // Verify initial local state
    var dbTrack = await dbService.getTrack('track-local-fav');
    expect(dbTrack, isNotNull);
    expect(dbTrack!.isDownloaded, isTrue);
    expect(dbTrack.localPath, equals('C:\\Music\\NCmus\\LocalFile.mp3'));

    // B. Create remote snapshot with updated metadata for existing track and one new track
    final remoteSnapshot = SyncSnapshot(
      version: 10,
      tracks: [
        {
          'id': 'track-local-fav',
          'title': 'New Updated Title',
          'artist': 'New Updated Artist',
          'duration_ms': 210000,
          'stream_url': 'https://example.com/new.mp3',
          'cover_url': 'https://example.com/new_cover.jpg',
          'source_name': 'Muzofond',
          'is_favorite': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        {
          'id': 'track-brand-new',
          'title': 'Brand New Track',
          'artist': 'Brand New Artist',
          'duration_ms': 180000,
          'stream_url': 'https://example.com/brand_new.mp3',
          'cover_url': null,
          'source_name': 'Hitmo',
          'is_favorite': 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
      ],
      theme: 'cyberpunk_neon',
    );

    // C. Perform merge
    await dbService.mergeRemoteSnapshot(remoteSnapshot);

    // D. Verify existing track has updated metadata but local_path and is_downloaded are PRESERVED!
    final updatedTrack = await dbService.getTrack('track-local-fav');
    expect(updatedTrack, isNotNull);
    expect(updatedTrack!.title, equals('New Updated Title'));
    expect(updatedTrack.artist, equals('New Updated Artist'));
    expect(updatedTrack.isFavorite, isTrue);
    expect(updatedTrack.coverUrl, equals('https://example.com/new_cover.jpg'));
    // CRITICAL REQUIREMENT: local_path and is_downloaded MUST NOT be wiped out
    expect(updatedTrack.isDownloaded, isTrue);
    expect(updatedTrack.localPath, equals('C:\\Music\\NCmus\\LocalFile.mp3'));

    // E. Verify brand new track is inserted with is_downloaded = false and local_path = null
    final newTrack = await dbService.getTrack('track-brand-new');
    expect(newTrack, isNotNull);
    expect(newTrack!.title, equals('Brand New Track'));
    expect(newTrack.isDownloaded, isFalse);
    expect(newTrack.localPath, isNull);

    // F. Verify db_version in sync_meta is updated
    final dbVersion = await dbService.getLocalDbVersion();
    expect(dbVersion, equals(10));
  });

  test('3. Recording and clearing sync_outbox entries', () async {
    // Verify initially empty
    var outbox = await dbService.getOutboxEntries();
    expect(outbox.isEmpty, isTrue);

    // Add entries
    await dbService.addOutboxAction('toggle_favorite', {'id': 'track-1', 'is_favorite': true});
    await dbService.addOutboxAction('add_track', {'id': 'track-2', 'title': 'New Song'});

    outbox = await dbService.getOutboxEntries();
    expect(outbox.length, equals(2));
    expect(outbox[0]['action'], equals('toggle_favorite'));
    expect(outbox[1]['action'], equals('add_track'));

    final payload = jsonDecode(outbox[0]['payload'] as String);
    expect(payload['id'], equals('track-1'));
    expect(payload['is_favorite'], isTrue);

    // Clear outbox
    await dbService.clearOutbox();
    outbox = await dbService.getOutboxEntries();
    expect(outbox.isEmpty, isTrue);
  });

  test('4. SyncWorker Step A (Push flow when outbox has entries)', () async {
    // Add outbox entry
    await dbService.addOutboxAction('favorite', {'id': 'track-100'});
    await dbService.setLocalDbVersion(1);

    bool pushCalled = false;
    final mockClient = MockClient((request) async {
      if (request.method == 'POST') {
        pushCalled = true;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], equals('alex'));
        expect(body['password'], equals('secret'));
        expect(body['action'], equals('push'));

        // Return 302 redirect like GAS
        return http.Response(
          '',
          302,
          headers: {'location': 'https://script.googleusercontent.com/macros/echo?token=xyz'},
        );
      } else if (request.method == 'GET' && request.url.host == 'script.googleusercontent.com') {
        return http.Response(
          jsonEncode({'status': 'ok', 'version': 2, 'action': 'updated'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 404);
    });

    final cloudService = CloudSyncService(client: mockClient);
    final worker = SyncWorker(dbService: dbService, cloudService: cloudService);
    worker.currentUsername = 'alex';
    worker.currentPassword = 'secret';

    final result = await worker.syncNow();
    expect(result, isTrue);
    expect(pushCalled, isTrue);

    // Outbox should now be empty and localDbVersion updated to 2
    final outbox = await dbService.getOutboxEntries();
    expect(outbox.isEmpty, isTrue);
    final localVersion = await dbService.getLocalDbVersion();
    expect(localVersion, equals(2));
  });

  test('5. SyncWorker Step B (Pull flow when outbox is empty and remote is ahead)', () async {
    // Outbox is empty, localDbVersion is 2
    await dbService.clearOutbox();
    await dbService.setLocalDbVersion(2);

    bool checkVersionCalled = false;
    bool pullCalled = false;

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['action'];
      if (action == 'check_version') {
        checkVersionCalled = true;
        return http.Response(
          jsonEncode({'version': 3, 'exists': true}),
          200,
        );
      } else if (action == 'pull') {
        pullCalled = true;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'version': 3,
            'sync_data': {
              'version': 3,
              'tracks': [
                {
                  'id': 'remote-track-99',
                  'title': 'Remote Track',
                  'artist': 'Cloud Artist',
                  'duration_ms': 200000,
                  'stream_url': 'https://example.com/remote.mp3',
                  'cover_url': null,
                  'source_name': 'Hitmo',
                  'is_favorite': 1,
                  'created_at': DateTime.now().millisecondsSinceEpoch,
                }
              ],
              'playlists': [],
              'theme': 'cyberpunk_neon',
            }
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    final cloudService = CloudSyncService(client: mockClient);
    final worker = SyncWorker(dbService: dbService, cloudService: cloudService);
    worker.currentUsername = 'alex';
    worker.currentPassword = 'secret';

    final result = await worker.syncNow();
    expect(result, isTrue);
    expect(checkVersionCalled, isTrue);
    expect(pullCalled, isTrue);

    // Track should now be merged in local DB and local version updated to 3
    final track = await dbService.getTrack('remote-track-99');
    expect(track, isNotNull);
    expect(track!.title, equals('Remote Track'));
    expect(track.isDownloaded, isFalse);
    expect(await dbService.getLocalDbVersion(), equals(3));
  });

  test('6. Blacklist sync and outbox integration', () async {
    // A. Add to blacklist via addToBlacklist
    await dbService.addToBlacklist('Numb (Official Music Video) [Remix]', 'Linkin Park');

    // Verify outbox entry logged
    final outbox = await dbService.getOutboxEntries();
    expect(outbox.length, equals(1));
    expect(outbox.first['action'], equals('blacklist_add'));
    final payload = jsonDecode(outbox.first['payload'] as String);
    expect(payload['title'], equals('Numb (Official Music Video) [Remix]'));
    expect(payload['artist'], equals('Linkin Park'));
    expect(payload['normalized'], equals('numb'));

    // Verify getAllBlacklistedNormalized & getBlacklistRaw
    final normalized = await dbService.getAllBlacklistedNormalized();
    expect(normalized.contains('numb'), isTrue);

    final rawList = await dbService.getBlacklistRaw();
    expect(rawList.length, equals(1));
    expect(rawList.first, equals('numb|Linkin Park'));

    // B. Merge remote snapshot with another blacklisted track
    const remoteSnapshot = SyncSnapshot(
      version: 20,
      tracks: [],
      blacklist: ['in the end|Linkin Park', 'faint|Linkin Park'],
    );
    await dbService.mergeRemoteSnapshot(remoteSnapshot);

    final updatedNormalized = await dbService.getAllBlacklistedNormalized();
    expect(updatedNormalized.contains('numb'), isTrue);
    expect(updatedNormalized.contains('in the end'), isTrue);
    expect(updatedNormalized.contains('faint'), isTrue);

    final updatedRaw = await dbService.getBlacklistRaw();
    expect(updatedRaw.length, equals(3));
  });
}

