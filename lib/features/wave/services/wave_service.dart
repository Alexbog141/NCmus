import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../storage/models/track_entity.dart';
import 'nc_wave_service.dart';
import 'wave_recommendation_engine.dart';

/// Central Wave Service managing the lifecycle of infinite wave playback,
/// genre mixes, and deduplication through [WaveRecommendationEngine].
///
/// Fully autonomous from the UI: all queue replenishment subscriptions
/// and playback completion monitoring live here in the singleton.
class WaveService extends ChangeNotifier {
  static WaveService? _instance;

  /// Global shared singleton instance of [WaveService].
  static WaveService get instance => _instance ??= WaveService();

  /// Setter for testing or custom overrides.
  static set instance(WaveService service) => _instance = service;

  final WaveRecommendationEngine recommendationEngine;
  NCPlayerHandler? _handler;
  NCWaveService? _ncWaveService;
  StreamSubscription<PlaybackState>? _playbackSub;

  final List<TrackEntity> _waveQueue = <TrackEntity>[];

  bool _isActive = false;
  bool _isGenerating = false;
  String? _activeGenre;

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  /// Stream of user-facing status messages (e.g. offline alerts).
  Stream<String> get statusMessages => _statusController.stream;

  void notifyStatusMessage(String message) {
    if (!_statusController.isClosed) {
      _statusController.add(message);
    }
  }

  WaveService({
    WaveRecommendationEngine? recommendationEngine,
    NCPlayerHandler? handler,
    NCWaveService? ncWaveService,
  })  : recommendationEngine =
            recommendationEngine ?? WaveRecommendationEngine(),
        _handler = handler,
        _ncWaveService = ncWaveService {
    _instance = this;
    if (_handler != null) {
      attachHandler(_handler!);
    }
  }

  /// Attached audio player handler.
  NCPlayerHandler? get handler => _handler;

  /// Whether wave mode is currently active.
  bool get isActive => _isActive;
  bool get isWaveActive => _isActive;

  /// Whether track generation is currently in progress.
  bool get isGenerating => _isGenerating;

  /// Currently active genre or mix name (e.g., 'Мой Микс', 'Синтвейв & 80s').
  String? get activeGenre => _activeGenre;

  /// Isolated online Wave buffer.
  List<TrackEntity> get waveQueue => List<TrackEntity>.unmodifiable(_waveQueue);

  @visibleForTesting
  void setGeneratingForTest(bool val) {
    _isGenerating = val;
  }

  @visibleForTesting
  void setActiveForTest(bool val) {
    _isActive = val;
  }

  @visibleForTesting
  void addTrackToWaveQueueForTest(TrackEntity track) {
    _waveQueue.add(track);
  }

  /// Attaches the audio handler and sets up continuous playback monitoring.
  void attachHandler(NCPlayerHandler handler) {
    if (_handler == handler && _playbackSub != null) return;
    _handler = handler;
    _playbackSub?.cancel();
    _playbackSub = _handler!.playbackState.listen((_) => _checkAndRefillQueue());
  }

  /// Attaches or links the underlying [NCWaveService].
  void attachNCWaveService(NCWaveService service) {
    _ncWaveService = service;
  }

  /// Starts or restarts wave playback.
  ///
  /// Resets deadlocks if [forceRestart] is true or if wave is not active.
  /// Generates the initial batch of 5 tracks via [_initWaveSession].
  Future<void> startWave({String? genreId, bool forceRestart = false}) async {
    // Если запуск принудительный (клик пользователя) — сбрасываем любые зависшие блокировки
    if (forceRestart || !_isActive) {
      _isGenerating = false;
    }
    if (_isGenerating) {
      debugPrint('[WaveService] Генерация уже выполняется, пропускаем дубль');
      return;
    }
    _isGenerating = true;
    try {
      // Очистка старой сессии и генерация первой пачки треков
      await _initWaveSession(genreId);
    } catch (e, st) {
      debugPrint('[WaveService] Ошибка старта волны: $e\n$st');
    } finally {
      _isGenerating = false; // БЛОКИРОВКА ОБЯЗАНА СНИМАТЬСЯ ВСЕГДА
      notifyListeners();
    }
  }

  /// Initializes a fresh wave session:
  /// Requests 5 online tracks through [WaveRecommendationEngine], fills
  /// [_waveQueue], sets `currentSourceMode = AudioSourceMode.wave`, and plays track.
  Future<void> _initWaveSession(String? genreId) async {
    final genre = genreId ?? 'Мой Микс';
    _activeGenre = genre;
    recommendationEngine.clearHistory();
    _waveQueue.clear();

    if (_handler != null) {
      _handler!.currentSourceMode = AudioSourceMode.wave;
    }

    final tracks = await recommendationEngine
        .recommendTracks(genreId: genre, count: 5)
        .timeout(const Duration(seconds: 15));

    if (tracks.isEmpty) {
      debugPrint('[WaveService] Рекомендательный движок вернул пустую пачку треков');
      _isActive = false;
      if (_handler != null) {
        await _handler!.handleWaveExhausted();
      }
      notifyStatusMessage(
          'Нет подключения к сети и локального кэша для продолжения Волны');
      return;
    }

    for (final m in tracks) {
      final localPath = m.extras?['localPath'] as String?;
      final streamUrl =
          m.extras?['streamUrl'] as String? ?? (localPath == null ? m.id : '');
      _waveQueue.add(TrackEntity(
        id: (m.extras?['originalId'] as String?) ?? m.id,
        title: m.title,
        artist: m.artist ?? '',
        duration: m.duration ?? Duration.zero,
        streamUrl: streamUrl,
        localPath: localPath,
        coverUrl: m.artUri?.toString(),
        sourceName: 'wave',
        createdAt: DateTime.now(),
      ));
    }

    _isActive = true;

    // Достаем первый трек из буфера и запускаем воспроизведение
    final firstTrack = _waveQueue.removeAt(0);
    if (_handler != null) {
      await _handler!.setQueueAndPlay(
        [firstTrack.toMediaItem()],
        0,
        mode: AudioSourceMode.wave,
      );
      await _handler!.play();
    }

    // Держим в буфере всегда 3–5 онлайн-треков
    if (_waveQueue.length < 4) {
      unawaited(_replenishBuffer(count: 2));
    }

    final ncWave = _ncWaveService ?? NCWaveService.instance;
    if (ncWave != null) {
      ncWave.activeGenre = genre;
    }
  }

  /// Plays the next online wave track from the isolated buffer, and background
  /// replenishes 2 more recommendations to maintain a healthy buffer.
  Future<void> playNextWaveTrack() async {
    if (!_isActive) return;
    if (_handler != null) {
      _handler!.currentSourceMode = AudioSourceMode.wave;
    }

    // Если буфер пуст, догружаем онлайн-треки
    if (_waveQueue.isEmpty) {
      await _replenishBuffer(count: 3);
    }

    if (_waveQueue.isNotEmpty) {
      final nextTrack = _waveQueue.removeAt(0);
      if (_handler != null) {
        await _handler!.setQueueAndPlay(
          [nextTrack.toMediaItem()],
          0,
          mode: AudioSourceMode.wave,
        );
        await _handler!.play();
      }
    } else {
      _isActive = false;
      if (_handler != null) {
        await _handler!.handleWaveExhausted();
      }
      notifyStatusMessage(
          'Нет подключения к сети и локального кэша для продолжения Волны');
    }

    // Если в буфере осталось меньше 3-5 треков — фоном запрашиваем еще 2 новых
    if (_waveQueue.length < 4 && _isActive) {
      unawaited(_replenishBuffer(count: 2));
    }
    notifyListeners();
  }

  /// Background refill of the isolated wave queue buffer with online recommendations.
  Future<void> _replenishBuffer({int count = 2}) async {
    if (_isGenerating || !_isActive) return;
    _isGenerating = true;
    try {
      final newTracks = await recommendationEngine
          .recommendTracks(genreId: _activeGenre, count: count)
          .timeout(const Duration(seconds: 15));
      for (final m in newTracks) {
        final trackId = (m.extras?['originalId'] as String?) ?? m.id;
        if (!_waveQueue.any((t) => t.id == trackId)) {
          final localPath = m.extras?['localPath'] as String?;
          final streamUrl = m.extras?['streamUrl'] as String? ??
              (localPath == null ? m.id : '');
          _waveQueue.add(TrackEntity(
            id: trackId,
            title: m.title,
            artist: m.artist ?? '',
            duration: m.duration ?? Duration.zero,
            streamUrl: streamUrl,
            localPath: localPath,
            coverUrl: m.artUri?.toString(),
            sourceName: 'wave',
            createdAt: DateTime.now(),
          ));
        }
      }
    } catch (e, st) {
      debugPrint('[WaveService] Ошибка автоподгрузки онлайн-треков: $e\n$st');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Checks buffer and triggers background refill if needed.
  Future<void> _checkAndRefillQueue() async {
    if (!_isActive || _isGenerating || _handler == null) return;
    if (_waveQueue.length < 3) {
      unawaited(_replenishBuffer(count: 2));
    }
  }

  /// Stops wave playback, resets [_isActive = false], but DOES NOT break handler.
  void stopWave() {
    _isActive = false;
    _isGenerating = false;
    _activeGenre = null;
    _waveQueue.clear();

    if (_handler != null &&
        _handler!.currentSourceMode == AudioSourceMode.wave) {
      _handler!.currentSourceMode = AudioSourceMode.library;
    }

    final ncWave = _ncWaveService ?? NCWaveService.instance;
    if (ncWave != null && ncWave.isWaveActive) {
      ncWave.stopWave();
    }

    notifyListeners();
  }

  /// Starts or restarts the personal "Мой Микс" wave.
  Future<void> startMyMix({bool forceRestart = false}) async {
    await startWave(genreId: 'Мой Микс', forceRestart: forceRestart);
  }

  /// Starts wave playback tailored to a specific [genre] using [seeds].
  Future<void> startWaveForGenre(
    String genre,
    List<String> seeds, {
    bool forceRestart = false,
  }) async {
    await startWave(genreId: genre, forceRestart: forceRestart);
  }

  /// Utility to check whether a candidate track should be dropped as a duplicate/remix.
  bool shouldDiscardTrack(String artist, String title) {
    return recommendationEngine.isTrackDuplicate(artist, title);
  }

  /// Records a track into the sliding deduplication window.
  void recordTrack(String artist, String title) {
    recommendationEngine.recordTrack(artist, title);
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _playbackSub = null;
    _statusController.close();
    super.dispose();
  }
}
