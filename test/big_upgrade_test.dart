import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/library/services/local_storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService dbService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_upgrade_test_');
    dbService = DatabaseService.instance;
    dbService.setCustomPath(p.join(tempDir.path, 'upgrade_test.db'));
  });

  tearDown(() async {
    await dbService.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('Persistent Blacklist & Un-dislike: isTrackBlacklisted and removeFromBlacklist', () async {
    const title = 'After Dark [Remix]';
    const artist = 'Mr.Kitty';

    // 1. Initially not blacklisted
    expect(await dbService.isTrackBlacklisted(title, artist), isFalse);

    // 2. Add to blacklist
    await dbService.addToBlacklist(title, artist);
    expect(await dbService.isTrackBlacklisted(title, artist), isTrue);
    expect(await dbService.isTrackBlacklisted('After Dark (Slowed)', 'Mr.Kitty'), isTrue);
    expect(DatabaseService.blacklistCount.value, greaterThan(0));

    // 3. Remove from blacklist (un-dislike)
    await dbService.removeFromBlacklist(title, artist);
    expect(await dbService.isTrackBlacklisted(title, artist), isFalse);
  });

  test('Listening History and Top Artists: logPlayHistory, getListeningHistory, getTopArtists', () async {
    const track1 = MediaItem(
      id: 'history_test_1',
      title: 'Resonance',
      artist: 'HOME',
      duration: Duration(seconds: 212),
      artUri: null,
    );

    const track2 = MediaItem(
      id: 'history_test_2',
      title: 'decay',
      artist: 'HOME',
      duration: Duration(seconds: 180),
      artUri: null,
    );

    const track3 = MediaItem(
      id: 'history_test_3',
      title: 'Nightcall',
      artist: 'Kavinsky',
      duration: Duration(seconds: 259),
      artUri: null,
    );

    // Log history
    await dbService.logPlayHistory(track1);
    await dbService.logPlayHistory(track2);
    await dbService.logPlayHistory(track3);
    await dbService.logPlayHistory(track1); // Second play for HOME

    // Check history
    final history = await dbService.getListeningHistory(limit: 10);
    expect(history.length, equals(4));
    expect(history.first['title'], equals('Resonance'));

    // Check top artists
    final topArtists = await dbService.getTopArtists(limit: 5);
    expect(topArtists.isNotEmpty, isTrue);
    expect(topArtists.first['artist'], equals('HOME'));
    expect(topArtists.first['play_count'], equals(3));
  });

  test('LocalStorageService: scanAndSyncLocalFolder parses mp3 files and saves to SQLite', () async {
    final mockMusicDir = Directory(p.join(tempDir.path, 'Music', 'NCmus'));
    mockMusicDir.createSync(recursive: true);

    // Create a mock MP3 file
    final testMp3 = File(p.join(mockMusicDir.path, 'Daft Punk - Get Lucky.mp3'));
    testMp3.writeAsStringSync('mock mp3 binary content');

    final localService = LocalStorageService(
      dbService: dbService,
      customDirectory: mockMusicDir,
    );

    final addedCount = await localService.scanAndSyncLocalFolder();
    expect(addedCount, equals(1));

    // Verify track is in database
    final downloaded = await dbService.getAllDownloadedTracks();
    expect(downloaded.length, equals(1));
    expect(downloaded.first.artist, equals('Daft Punk'));
    expect(downloaded.first.title, equals('Get Lucky'));
    expect(downloaded.first.isDownloaded, isTrue);
    expect(downloaded.first.localPath, equals(testMp3.path));

    // Scanning again should add 0 new tracks
    final secondScanCount = await localService.scanAndSyncLocalFolder();
    expect(secondScanCount, equals(0));
  });

  test('NCPlayerHandler removeFromBlacklist synchronization', () async {
    final handler = NCPlayerHandler();
    addTearDown(() => handler.dispose());

    const item = MediaItem(
      id: 'test_item_dislike',
      title: 'Bad Song',
      artist: 'Annoying Artist',
      duration: Duration(seconds: 120),
    );

    // Dislike
    await handler.dislikeCurrentTrack(item);
    expect(await dbService.isTrackBlacklisted('Bad Song', 'Annoying Artist'), isTrue);

    // Un-dislike
    await handler.removeFromBlacklist(item);
    expect(await dbService.isTrackBlacklisted('Bad Song', 'Annoying Artist'), isFalse);
  });
}
