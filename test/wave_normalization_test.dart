import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/features/wave/services/wave_recommendation_engine.dart';
import 'package:ncmus/features/wave/services/wave_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveRecommendationEngine Title Normalization Tests', () {
    late WaveRecommendationEngine engine;

    setUp(() {
      engine = WaveRecommendationEngine();
    });

    test('normalizeTrackTitle cleans "Мокрые кроссы (Remix)" -> "мокрые кроссы"', () {
      final normalized = engine.normalizeTrackTitle('Мокрые кроссы (Remix)');
      expect(normalized, equals('мокрые кроссы'));
    });

    test('normalizeTrackTitle cleans "Трек feat. Артист" -> "трек"', () {
      final normalized = engine.normalizeTrackTitle('Трек feat. Артист');
      expect(normalized, equals('трек'));
    });

    test('normalizeTrackTitle cleans "Track [Slowed + Reverb]" -> "track"', () {
      final normalized = engine.normalizeTrackTitle('Track [Slowed + Reverb]');
      expect(normalized, equals('track'));
    });

    test('normalizeTrackTitle handles various bracketed and unbracketed remixes/edits', () {
      expect(engine.normalizeTrackTitle('Cyber City (VIP Mix)'), equals('cyber city'));
      expect(engine.normalizeTrackTitle('Nightcall (Radio Edit)'), equals('nightcall'));
      expect(engine.normalizeTrackTitle('Neon Dreams {Speed Up}'), equals('neon dreams'));
      expect(engine.normalizeTrackTitle('Midnight ft. Guest'), equals('midnight'));
      expect(engine.normalizeTrackTitle('Solaris [Prod. Master]'), equals('solaris'));
    });
  });

  group('WaveRecommendationEngine Deduplication & Sliding Window Tests', () {
    late WaveRecommendationEngine engine;

    setUp(() {
      engine = WaveRecommendationEngine();
    });

    test('Deduplicator blocks remix if original was already played', () {
      const artist = 'Тима Белорусских';
      const originalTitle = 'Мокрые кроссы';
      const remixTitle = 'Мокрые кроссы (Remix)';

      // 1. Initially candidate is not duplicate
      expect(engine.isTrackDuplicate(artist, remixTitle), isFalse);

      // 2. Play and record original track
      final added = engine.recordTrack(artist, originalTitle);
      expect(added, isTrue);

      // 3. Candidate remix must now be discarded/blocked
      expect(engine.isTrackDuplicate(artist, remixTitle), isTrue);
      expect(engine.isDuplicate(artist, remixTitle), isTrue);
    });

    test('Deduplicator blocks original if remix was already played', () {
      const artist = 'Kavinsky';
      const remixTitle = 'Nightcall (Drive Edit)';
      const originalTitle = 'Nightcall';

      engine.recordTrack(artist, remixTitle);
      expect(engine.isTrackDuplicate(artist, originalTitle), isTrue);
    });

    test('Different song by same artist is not marked as duplicate', () {
      const artist = 'Тима Белорусских';
      engine.recordTrack(artist, 'Мокрые кроссы');

      expect(engine.isTrackDuplicate(artist, 'Незабудка'), isFalse);
    });

    test('Sliding window retains at most 40 tracks and evicts oldest', () {
      // Add 40 distinct tracks
      for (var i = 0; i < 40; i++) {
        engine.recordTrack('Artist $i', 'Song $i');
      }
      expect(engine.historyLength, equals(40));
      expect(engine.isTrackDuplicate('Artist 0', 'Song 0'), isTrue);

      // Add 41st track - should evict Artist 0 | Song 0
      engine.recordTrack('Artist 40', 'Song 40');
      expect(engine.historyLength, equals(40));
      expect(engine.isTrackDuplicate('Artist 40', 'Song 40'), isTrue);
      expect(engine.isTrackDuplicate('Artist 0', 'Song 0'), isFalse);
    });

    test('clearHistory resets all recorded track keys', () {
      engine.recordTrack('Artist', 'Song');
      expect(engine.historyLength, equals(1));

      engine.clearHistory();
      expect(engine.historyLength, equals(0));
      expect(engine.isTrackDuplicate('Artist', 'Song'), isFalse);
    });
  });

  group('WaveService Lifecycle Tests', () {
    late WaveService waveService;
    late _FakeHandler handler;

    setUp(() {
      handler = _FakeHandler();
      final engine = WaveRecommendationEngine(
        onRecommend: ({genreId, count = 5}) async {
          return List.generate(
            count,
            (i) => MediaItem(
              id: 'wave_$i',
              title: 'Wave Track $i',
              artist: 'Wave Artist',
              extras: const {'source': 'wave', 'isWave': true},
            ),
          );
        },
      );
      waveService = WaveService(recommendationEngine: engine, handler: handler);
    });

    tearDown(() {
      waveService.dispose();
    });

    test('stopWave resets active state, genre, and notifies listeners', () {
      var notifyCount = 0;
      waveService.addListener(() => notifyCount++);

      waveService.stopWave();
      expect(waveService.isWaveActive, isFalse);
      expect(waveService.activeGenre, isNull);
      expect(notifyCount, equals(1));
    });

    test('startMyMix and startWaveForGenre manage active genre state and reset interrupted session', () async {
      await waveService.startMyMix(forceRestart: true);
      expect(waveService.isWaveActive, isTrue);
      expect(waveService.activeGenre, equals('Мой Микс'));

      await waveService.startWaveForGenre('Синтвейв & 80s', ['Synthwave']);
      expect(waveService.isWaveActive, isTrue);
      expect(waveService.activeGenre, equals('Синтвейв & 80s'));

      waveService.stopWave();
      expect(waveService.isWaveActive, isFalse);
      expect(waveService.activeGenre, isNull);
    });
  });
}

class _FakeHandler extends NCPlayerHandler {
  final List<MediaItem> _queue = <MediaItem>[];

  @override
  List<MediaItem> get queueItems => List<MediaItem>.unmodifiable(_queue);

  @override
  Future<void> setQueueAndPlay(
    List<MediaItem> items,
    int startIndex, {
    AudioSourceMode? mode,
  }) async {
    _queue.clear();
    _queue.addAll(items);
  }

  @override
  Future<void> appendToQueue(List<MediaItem> items) async {
    _queue.addAll(items);
  }

  @override
  Future<void> play() async {}
}
