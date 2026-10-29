import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/services/window_overlay_service.dart';
import 'package:ncmus/features/wave/services/wave_recommendation_engine.dart';
import 'package:ncmus/features/wave/services/wave_service.dart';

class _FakeAudioPlayerHandler extends NCPlayerHandler {
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
    int initialIndex, {
    AudioSourceMode? mode,
  }) async {
    if (mode != null) {
      currentSourceMode = mode;
    }
    _fakeQueue
      ..clear()
      ..addAll(items);
    _fakeIndex = initialIndex.clamp(0, items.isEmpty ? 0 : items.length - 1);
    mediaItem.add(items.isNotEmpty ? items[_fakeIndex] : null);
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

  group('Wave Queue Isolation & Mode Enforcement DoD Tests', () {
    late _FakeAudioPlayerHandler handler;
    late WaveRecommendationEngine engine;
    late WaveService waveService;

    setUp(() {
      handler = _FakeAudioPlayerHandler();
      engine = WaveRecommendationEngine(
        onRecommend: ({genreId, count = 5}) async {
          final tag = genreId ?? 'Cyberpunk';
          return List.generate(
            count,
            (i) => MediaItem(
              id: 'https://stream.mock/$tag/$i.mp3',
              title: '$tag Online Stream #$i',
              artist: '$tag Artist',
              extras: const {'source': 'wave'},
            ),
          );
        },
      );
      waveService = WaveService(
        recommendationEngine: engine,
        handler: handler,
      );
      WaveService.instance = waveService;
    });

    test('Тест 1: Запуск Волны устанавливает currentSourceMode == AudioSourceMode.wave', () async {
      expect(handler.currentSourceMode, equals(AudioSourceMode.library));
      expect(waveService.isActive, isFalse);

      await waveService.startWave(genreId: 'Cyberpunk');

      expect(waveService.isActive, isTrue);
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(handler.mediaItem.value, isNotNull);
      expect(handler.mediaItem.value!.extras?['source'], equals('wave'));
    });

    test(
        'Тест 2: Вызов skipToNext() в режиме Волны оставляет режим AudioSourceMode.wave и не подтягивает треки из локального списка базы данных',
        () async {
      // 1. Предварительно запускаем волну
      await waveService.startWave(genreId: 'Phonk');
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));

      final firstTrackId = handler.mediaItem.value?.id;
      expect(firstTrackId, isNotNull);

      // 2. Пользователь жмет скип (skipToNext)
      await handler.skipToNext();

      // Проверяем: режим остался AudioSourceMode.wave
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);

      // Проверяем: играет СЛЕДУЮЩИЙ онлайн-трек из буфера Волны, а не локальный трек
      final secondTrack = handler.mediaItem.value;
      expect(secondTrack, isNotNull);
      expect(secondTrack!.id, isNot(equals(firstTrackId)));
      expect(secondTrack.id, startsWith('https://stream.mock/'));
      expect(secondTrack.extras?['source'], equals('wave'));

      // 3. Еще один скип
      await handler.skipToNext();
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(handler.mediaItem.value!.extras?['source'], equals('wave'));
    });

    test(
        'Тест 3: Симуляция переключения оверлея (enableOverlay -> collapse -> expand -> restoreApp) НЕ меняет currentSourceMode и НЕ сбрасывает текущий играющий поток Волны',
        () async {
      final overlayService = WindowOverlayService.instance;

      // 1. Запуск волны
      await waveService.startWave(genreId: 'Synthwave');
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);

      final currentPlayingTrack = handler.mediaItem.value;
      expect(currentPlayingTrack, isNotNull);

      // 2. Симуляция открытия оверлея (сворачивание в плавающий орб)
      overlayService.isOverlayActive.value = true;
      overlayService.isExpanded.value = false;

      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);
      expect(handler.mediaItem.value, equals(currentPlayingTrack));

      // 3. Симуляция разворачивания оверлея в HUD
      overlayService.isExpanded.value = true;

      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);
      expect(handler.mediaItem.value, equals(currentPlayingTrack));

      // 4. Симуляция повторного сворачивания в орб
      overlayService.isExpanded.value = false;

      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);

      // 5. Симуляция восстановления полного окна (restoreApp)
      overlayService.isExpanded.value = false;
      overlayService.isOverlayActive.value = false;

      // Режим и играющий поток волны остаются абсолютно нетронутыми!
      expect(handler.currentSourceMode, equals(AudioSourceMode.wave));
      expect(waveService.isActive, isTrue);
      expect(handler.mediaItem.value, equals(currentPlayingTrack));
    });
  });
}
