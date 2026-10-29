import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/features/wave/services/wave_recommendation_engine.dart';
import 'package:ncmus/features/wave/services/wave_service.dart';

class _FakePlayerHandler extends NCPlayerHandler {
  final List<MediaItem> _fakeQueue = <MediaItem>[];
  int _fakeIndex = 0;
  bool playCalled = false;

  @override
  List<MediaItem> get queueItems => List<MediaItem>.unmodifiable(_fakeQueue);

  @override
  int get currentIndex => _fakeIndex;

  @override
  Future<void> setQueueAndPlay(
    List<MediaItem> items,
    int startIndex, {
    AudioSourceMode? mode,
  }) async {
    _fakeQueue.clear();
    _fakeQueue.addAll(items);
    _fakeIndex = startIndex;
  }

  @override
  Future<void> appendToQueue(List<MediaItem> items) async {
    _fakeQueue.addAll(items);
  }

  @override
  Future<void> play() async {
    playCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveService Lifecycle & State Lock DoD Tests', () {
    late _FakePlayerHandler handler;

    setUp(() {
      handler = _FakePlayerHandler();
    });

    test(
        'startWave(forceRestart: true) resets _isGenerating even upon simulated network/parsing failure',
        () async {
      // 1. Setup engine simulating a network / parsing exception
      final failingEngine = WaveRecommendationEngine(
        onRecommend: ({genreId, count = 5}) async {
          throw const FormatException('Simulated network parsing failure');
        },
      );

      final service = WaveService(
        recommendationEngine: failingEngine,
        handler: handler,
      );

      // 2. Artificially simulate stuck generation flag from an interrupted future / resize
      service.setGeneratingForTest(true);
      expect(service.isGenerating, isTrue);

      // 3. User clicks wave restart with forceRestart: true -> lock MUST be reset
      await service.startWave(forceRestart: true);

      // 4. Verify that lock is released and isGenerating is strictly false
      expect(service.isGenerating, isFalse);
    });

    test(
        'startWave() -> stopWave() -> startWave() lifecycle chain transitions cleanly and refills queue',
        () async {
      final engine = WaveRecommendationEngine();
      final service = WaveService(
        recommendationEngine: engine,
        handler: handler,
      );

      // --- Stage 1: Initial startWave() ---
      expect(service.isActive, isFalse);
      expect(service.isWaveActive, isFalse);
      expect(handler.queueItems, isEmpty);

      await service.startWave();

      expect(service.isActive, isTrue);
      expect(service.isWaveActive, isTrue);
      expect(service.isGenerating, isFalse);
      expect(handler.queueItems.isNotEmpty, isTrue);
      expect(handler.playCalled, isTrue);

      // --- Stage 2: stopWave() ---
      service.stopWave();

      expect(service.isActive, isFalse);
      expect(service.isWaveActive, isFalse);
      expect(service.isGenerating, isFalse);

      // Handler is NOT destroyed or broken
      expect(handler.queueItems.isNotEmpty, isTrue);

      // --- Stage 3: Second startWave() ---
      handler.playCalled = false;
      await service.startWave();

      expect(service.isActive, isTrue);
      expect(service.isWaveActive, isTrue);
      expect(handler.queueItems.isNotEmpty, isTrue);
      expect(handler.queueItems.length + service.waveQueue.length, equals(5));
      expect(handler.playCalled, isTrue);
    });
  });
}
