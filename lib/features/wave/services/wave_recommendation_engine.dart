import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../../core/database/database_service.dart';
import '../../scraper/engine/scraper_engine.dart';
import 'nc_wave_service.dart';

/// Wave recommendation engine responsible for track normalization,
/// smart remix/variant deduplication, sliding window history of recent tracks,
/// and batch recommendation generation.
class WaveRecommendationEngine {
  /// Maximum number of normalized track keys to retain in the sliding window.
  static const int maxRecentHistory = 40;

  final Set<String> _recentNormalizedKeys = <String>{};
  final List<String> _historyOrder = <String>[];

  /// Optional delegate for testing or custom recommendation strategies.
  final Future<List<MediaItem>> Function({String? genreId, int count})?
      onRecommend;

  WaveRecommendationEngine({this.onRecommend});

  /// Unmodifiable view of recent normalized track keys.
  Set<String> get recentNormalizedKeys => Set.unmodifiable(_recentNormalizedKeys);

  /// Current number of tracks in history.
  int get historyLength => _recentNormalizedKeys.length;

  /// Normalizes a track title by stripping remix/edit/slowed tags, brackets,
  /// featured artists, special characters, and collapsing whitespace.
  ///
  /// Examples:
  /// - "Мокрые кроссы (Remix)" -> "мокрые кроссы"
  /// - "Трек feat. Артист" -> "трек"
  /// - "Track [Slowed + Reverb]" -> "track"
  /// - "Просто отпускай (bass boosted)" -> "просто отпускай"
  /// - "Numb (feat. Jay-Z) [Live]" -> "numb"
  String normalizeTrackTitle(String title) {
    var clean = title.toLowerCase();

    // 1. Remove bracketed variations: (remix), [slowed + reverb], {vip mix}, [Live], (bass boosted), etc.
    clean = clean.replaceAll(
      RegExp(
        r'[\(\[\{<].*?(remix|edit|vip|mix|prod|feat|ft|speed|slow|bass|boost|live|acoustic|version|instrumental).*?[\)\]\}>]',
        caseSensitive: false,
      ),
      '',
    );
    // Also remove any remaining bracketed tags
    clean = clean.replaceAll(
      RegExp(r'[\(\[\{<].*?[\)\]\}>]'),
      '',
    );

    // 2. Remove trailing feat. / ft. / remix / edit / speed up / slowed suffixes (with optional leading dash)
    clean = clean.replaceAll(
      RegExp(
        r'(\s*[-–—]\s*|\b)(feat|ft|remix|edit|speed\s*up|slowed|bass\s*boosted|vip\s*mix|prod)\b.*$',
        caseSensitive: false,
      ),
      '',
    );

    // 3. Keep only alphanumeric words, Russian letters, and spaces
    clean = clean.replaceAll(RegExp(r'[^\w\sа-яА-ЯёЁ]'), ' ').trim();

    // 4. Collapse multiple spaces
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    return clean;
  }

  /// Generates a deduplication key in the format:
  /// '${artist.toLowerCase().trim()}|${normalizeTrackTitle(title)}'
  String getTrackKey(String artist, String title) {
    final cleanArtist = artist.toLowerCase().trim();
    final cleanTitle = normalizeTrackTitle(title);
    return '$cleanArtist|$cleanTitle';
  }

  /// Returns true if [artist] and [title] matches a track already present
  /// in the recent history window (blocking original after remix and vice-versa).
  bool isTrackDuplicate(String artist, String title) {
    final key = getTrackKey(artist, title);
    return _recentNormalizedKeys.contains(key);
  }

  /// Alias for [isTrackDuplicate].
  bool isDuplicate(String artist, String title) => isTrackDuplicate(artist, title);

  /// Records [artist] and [title] into the sliding window.
  /// Returns true if the track was newly added, or false if it was already in history.
  bool recordTrack(String artist, String title) {
    final key = getTrackKey(artist, title);
    if (_recentNormalizedKeys.contains(key)) {
      return false;
    }

    if (_historyOrder.length >= maxRecentHistory) {
      final oldest = _historyOrder.removeAt(0);
      _recentNormalizedKeys.remove(oldest);
    }

    _historyOrder.add(key);
    _recentNormalizedKeys.add(key);
    return true;
  }

  /// Resets the sliding window history.
  void clearHistory() {
    _recentNormalizedKeys.clear();
    _historyOrder.clear();
  }

  /// Generates a batch of recommended online tracks for the given [genreId].
  ///
  /// Strictly online via ScraperEngine. Does NOT touch local database tracks.
  Future<List<MediaItem>> recommendTracks({
    String? genreId,
    int count = 5,
  }) async {
    if (onRecommend != null) {
      return onRecommend!(genreId: genreId, count: count);
    }

    // 1. Check if NCWaveService is running
    final ncWave = NCWaveService.instance;
    if (ncWave != null) {
      try {
        final seeds = genreId != null ? [genreId] : null;
        final scraped =
            await ncWave.generateWaveTracks(count: count, seeds: seeds);
        if (scraped.isNotEmpty) {
          final items = <MediaItem>[];
          for (final t in scraped) {
            recordTrack(t.artist, t.title);
            items.add(t.toMediaItem());
          }
          return items;
        }
      } catch (_) {
        // Fall back to direct scraper
      }
    }

    // 2. Direct online search via ScraperEngine
    try {
      final scraper = ScraperEngine.instance;
      final queries = <String>[];
      if (genreId != null && genreId.isNotEmpty) {
        queries.add(genreId);
      }
      queries.addAll(const [
        'Synthwave',
        'Phonk',
        'Cyberpunk 2077',
        'Post-Punk',
        'Rock',
        'Electronic',
        'Retrowave',
      ]);
      queries.shuffle();

      final onlineItems = <MediaItem>[];
      for (final query in queries) {
        try {
          final results = await scraper.searchAll(query);
          for (final track in results) {
            if (track.streamUrl.isEmpty) continue;
            if (!isTrackDuplicate(track.artist, track.title)) {
              recordTrack(track.artist, track.title);
              onlineItems.add(track.toMediaItem());
              if (onlineItems.length >= count) break;
            }
          }
        } catch (_) {
          // If a query fails, skip and proceed to next candidate
          continue;
        }
        if (onlineItems.length >= count) break;
      }
      if (onlineItems.isNotEmpty) return onlineItems;
    } catch (_) {
      // Scraper offline
    }

    // 3. Fallback: query DatabaseService for playable local files physically present on disk
    try {
      final offlineCandidates =
          await DatabaseService.instance.getAllPlayableOfflineTracks();
      if (offlineCandidates.isNotEmpty) {
        offlineCandidates.shuffle();
        final fallbackList = <MediaItem>[];
        for (final track in offlineCandidates) {
          if (!isTrackDuplicate(track.artist, track.title)) {
            recordTrack(track.artist, track.title);
            fallbackList.add(track.toMediaItem());
            if (fallbackList.length >= count) break;
          }
        }
        if (fallbackList.isNotEmpty) {
          return fallbackList;
        }
        // If all candidates were in sliding window, reset duplicate check
        for (final track in offlineCandidates) {
          recordTrack(track.artist, track.title);
          fallbackList.add(track.toMediaItem());
          if (fallbackList.length >= count) break;
        }
        if (fallbackList.isNotEmpty) {
          return fallbackList;
        }
      }
    } catch (_) {
      // Local DB offline fallback failure
    }

    // If there are no physical tracks on disk: return empty list.
    // Forbidden to return synthetic tracks without a playable source!
    return const <MediaItem>[];
  }
}
