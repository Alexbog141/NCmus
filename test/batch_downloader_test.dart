import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/library/services/batch_downloader_service.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BatchDownloaderService - Filename Sanitization Tests', () {
    test('sanitizeFileName removes forbidden filesystem characters', () {
      expect(
        BatchDownloaderService.sanitizeFileName(r'AC/DC - Highway to Hell: Live?.mp3'),
        'ACDC - Highway to Hell Live.mp3',
      );

      expect(
        BatchDownloaderService.sanitizeFileName(r'Artist *<Special>|Edition? - "Song" \ 2024.mp3'),
        'Artist SpecialEdition - Song 2024.mp3',
      );

      expect(
        BatchDownloaderService.sanitizeFileName('Track Without Extension'),
        'Track Without Extension.mp3',
      );

      expect(
        BatchDownloaderService.sanitizeFileName(r'  ///:::***???   '),
        'track.mp3',
      );

      expect(
        BatchDownloaderService.sanitizeFileName(''),
        'track.mp3',
      );
    });
  });

  group('BatchDownloaderService - Database Sync & Entity Mapping Tests', () {
    late Directory tempDir;
    late DatabaseService dbService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ncmus_batch_test_');
      final dbPath = p.join(tempDir.path, 'test_batch.db');
      dbService = DatabaseService.instance;
      dbService.setCustomPath(dbPath);
    });

    tearDown(() async {
      await dbService.close();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Isolated DB track status updates from STREAM to LOCAL', () async {
      final initialTrack = TrackEntity(
        id: 'track_test_101',
        title: 'Cyber Rain',
        artist: 'Neon Runner',
        duration: const Duration(minutes: 3, seconds: 20),
        streamUrl: 'https://cdn.example.com/audio/cyber_rain.mp3',
        localPath: null,
        sourceName: 'hitmo',
        isDownloaded: false,
        isFavorite: true,
        createdAt: DateTime.now(),
      );

      // 1. Insert stream track
      await dbService.insertOrUpdateTrack(initialTrack);

      final inserted = await dbService.getTrack(initialTrack.id);
      expect(inserted, isNotNull);
      expect(inserted!.isDownloaded, isFalse);
      expect(inserted.localPath, isNull);

      final downloadedBefore = await dbService.getAllDownloadedTracks();
      expect(downloadedBefore.any((t) => t.id == initialTrack.id), isFalse);

      // 2. Simulate download and save local file
      final fakeLocalFile = File(p.join(tempDir.path, 'Neon Runner - Cyber Rain.mp3'));
      await fakeLocalFile.writeAsBytes([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]); // ID3 header dummy

      // 3. Update status to local via DatabaseService
      final updatedTrack = initialTrack.copyWith(
        isDownloaded: true,
        localPath: fakeLocalFile.path,
      );

      var libraryChangedEmitted = false;
      final sub = dbService.libraryChanges.listen((_) {
        libraryChangedEmitted = true;
      });

      await dbService.insertOrUpdateTrack(updatedTrack);
      await dbService.markAsDownloaded(initialTrack.id, fakeLocalFile.path);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(libraryChangedEmitted, isTrue);
      await sub.cancel();

      // 4. Verify entity status and mapping in DB
      final savedInDb = await dbService.getTrack(initialTrack.id);
      expect(savedInDb, isNotNull);
      expect(savedInDb!.isDownloaded, isTrue);
      expect(savedInDb.localPath, fakeLocalFile.path);

      final downloadedList = await dbService.getAllDownloadedTracks();
      expect(downloadedList.length, 1);
      expect(downloadedList.first.id, initialTrack.id);
      expect(downloadedList.first.title, 'Cyber Rain');
      expect(downloadedList.first.artist, 'Neon Runner');
      expect(downloadedList.first.localPath, fakeLocalFile.path);
    });

    test('BatchDownloaderService initializes with custom directory and tracks states', () async {
      final dio = Dio();
      final musicDir = Directory(p.join(tempDir.path, 'Music', 'NCmus'));
      await musicDir.create(recursive: true);

      final downloader = BatchDownloaderService(
        dbService: dbService,
        dio: dio,
        customMusicDirectory: musicDir,
      );

      final track = TrackEntity(
        id: 'track_mock_202',
        title: 'Synthetic Dreams',
        artist: 'Glitch Mob',
        duration: const Duration(seconds: 180),
        streamUrl: 'https://mock.stream/song.mp3',
        localPath: null,
        sourceName: 'muzofond',
        isDownloaded: false,
        isFavorite: false,
        createdAt: DateTime.now(),
      );

      await dbService.insertOrUpdateTrack(track);

      expect(downloader.isDownloading, isFalse);
      expect(downloader.isCancelled, isFalse);

      final dir = await downloader.getMusicDirectory();
      expect(dir.existsSync(), isTrue);
      expect(p.normalize(dir.path), p.normalize(musicDir.path));

      // Test cancel call
      downloader.cancel();
      expect(downloader.isCancelled, isTrue);
      expect(downloader.isDownloading, isFalse);
    });
  });
}
