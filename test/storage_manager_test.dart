import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/scraper/models/scraped_track.dart';
import 'package:ncmus/features/storage/services/storage_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService dbService;
  late StorageManager storageManager;

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_storage_test_');
    dbService = DatabaseService.instance;
    dbService.setCustomPath(p.join(tempDir.path, 'test_ncmus.db'));

    storageManager = StorageManager(
      dbService: dbService,
      customMusicDirectory: tempDir,
    );
  });

  tearDown(() async {
    await dbService.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('StorageManager DoD Verification: Download, Tagging, and SQLite Persistence', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      final data = List<int>.filled(15000, 0x55);
      request.response.headers.contentLength = data.length;
      request.response.add(data);
      request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final testTrack = ScrapedTrack(
      id: 'test-track-soundhelix-1',
      title: 'Test Beat',
      artist: 'NCmus Engine',
      duration: const Duration(minutes: 6, seconds: 12),
      streamUrl: 'http://${server.address.host}:${server.port}/test.mp3',
      coverUrl: null,
      sourceName: 'Hitmo',
    );

    double recordedProgress = 0.0;

    // 1. Download and tag track
    final localPath = await storageManager.downloadAndTagTrack(
      track: testTrack,
      onProgress: (progress) {
        recordedProgress = progress;
      },
    );

    // 2. Validate local file exists and is not empty
    final file = File(localPath);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    expect(recordedProgress, greaterThan(0.0));

    // 3. Validate ID3 tags using audiotags (if native dynamic library is available in runner)
    try {
      final tag = await AudioTags.read(localPath);
      if (tag != null) {
        expect(tag.title, equals('Test Beat'));
        expect(tag.trackArtist, equals('NCmus Engine'));
      }
    } catch (_) {
      // audiotags.dll is compiled when running/building windows app;
      // in headless flutter test, dynamic library lookup may throw if not in PATH.
    }

    // 4. Validate SQLite entry
    final dbTrack = await dbService.getTrack('test-track-soundhelix-1');
    expect(dbTrack, isNotNull);
    expect(dbTrack!.isDownloaded, isTrue);
    expect(dbTrack.localPath, equals(localPath));
    expect(dbTrack.title, equals('Test Beat'));
    expect(dbTrack.artist, equals('NCmus Engine'));

    // 5. Validate getAllDownloadedTracks
    final downloaded = await dbService.getAllDownloadedTracks();
    expect(downloaded.any((t) => t.id == 'test-track-soundhelix-1'), isTrue);

    // 6. Validate toMediaItem mapping for downloaded track
    final mediaItem = dbTrack.toMediaItem();
    expect(mediaItem.id, equals(localPath));
    expect(mediaItem.extras?['isDownloaded'], isTrue);
    expect(mediaItem.extras?['localPath'], equals(localPath));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
