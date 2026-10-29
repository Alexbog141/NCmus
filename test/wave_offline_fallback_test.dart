import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audio_service/audio_service.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';
import 'package:ncmus/features/wave/services/wave_recommendation_engine.dart';
import 'package:ncmus/features/wave/services/wave_service.dart';

class MockPlayerHandler extends NCPlayerHandler {
  bool handleWaveExhaustedCalled = false;
  List<MediaItem> fakeQueue = [];

  @override
  Future<void> handleWaveExhausted() async {
    handleWaveExhaustedCalled = true;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> setQueueAndPlay(
    List<MediaItem> items,
    int initialIndex, {
    AudioSourceMode? mode,
  }) async {
    fakeQueue = List.from(items);
  }

  @override
  Future<void> play() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService dbService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_wave_test_');
    dbService = DatabaseService.instance;
    dbService.setCustomPath(p.join(tempDir.path, 'test_wave.db'));
  });

  tearDown(() async {
    await dbService.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Wave Offline Crash Elimination & Real Cached Fallback Tests', () {
    test('1. Empty network with NO local files returns empty list [] and NO synthetics',
        () async {
      final engine = WaveRecommendationEngine();

      // Recommend tracks when no network is mocked / scraper returns 0,
      // and database has no downloaded physical files on disk.
      final results = await engine.recommendTracks(genreId: 'Synthwave', count: 5);

      // Must return empty list, NOT fake NC-Wave Synthetics
      expect(results, isEmpty);
      expect(results.any((t) => t.artist == 'NC-Wave Synthetics'), isFalse);
      expect(results.any((t) => t.id.startsWith('nc_wave_')), isFalse);
    });

    test('2. Empty network with REAL local files returns only tracks with physical files',
        () async {
      // Create a dummy local audio file on disk
      final localAudioFile = File(p.join(tempDir.path, 'valid_track.mp3'));
      localAudioFile.writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]); // Non-empty file

      final realTrack = TrackEntity(
        id: 'real-local-1',
        title: 'Master of Puppets',
        artist: 'Metallica',
        duration: const Duration(minutes: 8, seconds: 35),
        streamUrl: 'https://remote.mirror/mop.mp3',
        localPath: localAudioFile.path,
        isDownloaded: true,
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );

      // Track with non-existent local file (should be excluded)
      final missingTrack = TrackEntity(
        id: 'missing-local-2',
        title: 'Ghost Track',
        artist: 'Ghost Artist',
        duration: const Duration(minutes: 3),
        streamUrl: 'https://remote.mirror/ghost.mp3',
        localPath: p.join(tempDir.path, 'does_not_exist.mp3'),
        isDownloaded: true,
        sourceName: 'Hitmo',
        createdAt: DateTime.now(),
      );

      await dbService.insertOrUpdateTrack(realTrack);
      await dbService.insertOrUpdateTrack(missingTrack);

      final engine = WaveRecommendationEngine();
      final results = await engine.recommendTracks(genreId: 'Rock', count: 5);

      // Should return the real local track with physical file
      expect(results.isNotEmpty, isTrue);
      expect(results.length, equals(1));
      expect(results.first.title, equals('Master of Puppets'));
      expect(results.first.artist, equals('Metallica'));

      // Validate playable source
      final extras = results.first.extras;
      expect(extras, isNotNull);
      final localPath = extras!['localPath'] as String?;
      expect(localPath, isNotNull);
      expect(File(localPath!).existsSync(), isTrue);

      // Strictly no synthetic fake tracks
      expect(results.any((t) => t.artist == 'NC-Wave Synthetics'), isFalse);
      expect(results.any((t) => t.id.startsWith('nc_wave_')), isFalse);
    });

    test('3. WaveService handles empty recommendations without crashing and notifies UI',
        () async {
      final mockHandler = MockPlayerHandler();
      // Recommendation engine with empty result delegate (simulating complete network + cache outage)
      final engine = WaveRecommendationEngine(
        onRecommend: ({String? genreId, int count = 5}) async => <MediaItem>[],
      );

      final waveService = WaveService(
        recommendationEngine: engine,
        handler: mockHandler,
      );

      String? receivedStatusMessage;
      final statusSub = waveService.statusMessages.listen((msg) {
        receivedStatusMessage = msg;
      });

      // Start wave
      await waveService.startWave(genreId: 'Мой Микс', forceRestart: true);

      // Wave should not be active
      expect(waveService.isActive, isFalse);
      expect(waveService.isGenerating, isFalse);
      expect(waveService.waveQueue, isEmpty);

      // Player handler should be transitioned to idle
      expect(mockHandler.handleWaveExhaustedCalled, isTrue);

      // Allow broadcast stream microtasks to flush
      await pumpEventQueue();

      // Status message published
      expect(receivedStatusMessage, isNotNull);
      expect(
        receivedStatusMessage,
        contains('Нет подключения к сети и локального кэша для продолжения Волны'),
      );

      await statusSub.cancel();
      waveService.dispose();
    });
  });
}
