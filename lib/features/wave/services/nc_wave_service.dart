import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../scraper/models/scraped_track.dart';
import '../../storage/models/track_entity.dart';
import 'wave_recommendation_engine.dart';
import 'wave_service.dart';

/// "NC-Wave" (NC-Волна) infinite smart stream generator.
///
/// Features:
/// - Instant wave startup: finds the first matching track and immediately starts
///   playback without waiting for the entire batch to download.
/// - Background replenishment: async preloading of remaining tracks into queue.
/// - Smart title deduplication (Title Normalization): strips tags like (remix),
///   [slowed], (bass boosted), (feat. ...) to prevent duplicate song versions.
/// - Session deduplication cache [Set<String> _playedTrackIds] and [_playedNormalizedTitles].
/// - Artist variety protection: prevents two consecutive tracks from the same artist.
/// - Dynamic seed expansion & shuffling: picks top 1-2 tracks per query.
/// - Persistent SQLite blacklist ([dislikeCurrentTrack] / [blacklistCurrentTrack]).
/// - Genre Hub integration with dedicated [startWaveForGenre] and active indicator.
class NCWaveService extends ChangeNotifier {
  /// Singleton or active shared instance accessible globally.
  static NCWaveService? instance;

  final NCPlayerHandler handler;
  final ScraperEngine scraperEngine;
  final DatabaseService dbService;
  final http.Client _httpClient;

  StreamSubscription<PlaybackState>? _playbackSub;
  bool _isWaveActive = false;
  bool _isGenerating = false;

  /// The currently active genre wave name (e.g. 'Киберпанк', 'Фонк', 'Мой Микс').
  String? activeGenre;

  List<String>? _activeSeeds;

  /// Session tracking cache of played track IDs, URLs, and deduplication keys.
  final Set<String> _playedTrackIds = <String>{};

  /// Normalized titles of tracks played during the session to eliminate remixes.
  final Set<String> _playedNormalizedTitles = <String>{};

  /// Blacklisted track hashes ('artist - title'), IDs and normalized titles.
  final Set<String> _blacklist = <String>{};
  final Set<String> _blacklistedTrackIds = <String>{};
  final Set<String> _blacklistedTitles = <String>{};

  /// Name of the last added artist to maintain variety and prevent back-to-back tracks.
  String? _lastArtist;

  final Random _random = Random();

  /// Dynamic genre seeds for empty or sparse media libraries.
  static const List<String> genreSeeds = [
    'Post-Punk',
    'Cyberpunk',
    'Synthwave',
    'Phonk',
    'Rock',
    'Alternative',
    'Indie',
    'Electronic',
    'Nu Metal',
    'Dark Techno',
    'Alternative Rock',
  ];

  /// Recommendation engine managing title normalization and sliding deduplication window.
  final WaveRecommendationEngine recommendationEngine =
      WaveRecommendationEngine();

  NCWaveService({
    required this.handler,
    required this.scraperEngine,
    DatabaseService? dbService,
    http.Client? httpClient,
  })  : dbService = dbService ?? DatabaseService.instance,
        _httpClient = httpClient ?? http.Client() {
    instance = this;
    handler.waveService = this;
    WaveService.instance.attachNCWaveService(this);
    WaveService.instance.attachHandler(handler);
    unawaited(_loadBlacklistFromDb());
  }

  bool get isWaveActive => _isWaveActive;

  /// Unmodifiable view of played track IDs for inspection and testing.
  Set<String> get playedTrackIds => Set.unmodifiable(_playedTrackIds);

  /// Unmodifiable view of played normalized titles for inspection and testing.
  Set<String> get playedNormalizedTitles =>
      Set.unmodifiable(_playedNormalizedTitles);

  /// Unmodifiable view of the blacklist hashes ('artist - title').
  Set<String> get blacklist => Set.unmodifiable(_blacklist);

  /// Unmodifiable view of blacklisted track IDs.
  Set<String> get blacklistedTrackIds =>
      Set.unmodifiable(_blacklistedTrackIds);

  /// Unmodifiable view of blacklisted titles.
  Set<String> get blacklistedTitles => Set.unmodifiable(_blacklistedTitles);

  /// The most recent artist added to the wave.
  String? get lastArtist => _lastArtist;

  /// Active seeds if wave was configured for a specific genre/mood.
  List<String>? get activeSeeds =>
      _activeSeeds != null ? List.unmodifiable(_activeSeeds!) : null;

  /// Generates a standardized comparison hash: "normalized_artist - normalized_title".
  static String getTrackHash(String? artist, String? title) {
    final normArtist = normalizeArtist(artist);
    final normTitle = normalizeTitle(title ?? '');
    return '$normArtist - $normTitle';
  }

  /// Normalizes track title using [WaveRecommendationEngine].
  static String normalizeTitle(String title) {
    if (title.isEmpty) return '';
    return WaveRecommendationEngine().normalizeTrackTitle(title);
  }

  /// Normalizes artist name for comparison.
  static String normalizeArtist(String? artist) {
    if (artist == null || artist.isEmpty) return '';
    var cleaned = artist.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{<].*?[\)\]\}>]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clears the session deduplication cache and artist tracker.
  void clearSessionCache() {
    _playedTrackIds.clear();
    _playedNormalizedTitles.clear();
    _lastArtist = null;
    recommendationEngine.clearHistory();
  }

  /// Restores blacklisted tracks from SQLite blacklist table and legacy key-value store.
  Future<void> _loadBlacklistFromDb() async {
    try {
      final titles = await dbService.getAllBlacklistedNormalized();
      _blacklistedTitles.addAll(titles);

      final rawList = await dbService.getBlacklistRaw();
      for (final raw in rawList) {
        final parts = raw.split('|');
        if (parts.length >= 2) {
          final normT = parts[0].trim();
          final art = parts.sublist(1).join('|').trim();
          final hash = getTrackHash(art, normT);
          _blacklist.add(hash);
          _blacklistedTrackIds.add(hash);
          if (normT.isNotEmpty) _blacklistedTitles.add(normT);
        } else if (raw.isNotEmpty) {
          _blacklistedTitles.add(normalizeTitle(raw));
        }
      }

      final raw = await dbService.getSyncMeta('wave_blacklist');
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final str = item.toString().trim();
            if (str.isNotEmpty) {
              _blacklist.add(str);
              _blacklistedTrackIds.add(str);
              if (str.contains(' - ')) {
                final parts = str.split(' - ');
                if (parts.length >= 2) {
                  final normT = normalizeTitle(parts.sublist(1).join(' - ').trim());
                  if (normT.isNotEmpty) _blacklistedTitles.add(normT);
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Best-effort loading
    }
  }

  /// Persists current blacklist to SQLite key-value store.
  Future<void> _persistBlacklist() async {
    try {
      await dbService.setSyncMeta(
        'wave_blacklist',
        jsonEncode(_blacklist.toList()),
      );
    } catch (_) {
      // Best-effort persistence
    }
  }

  /// Dislikes and bans [track] (or currently playing track) in SQLite and memory.
  ///
  /// 1. Writes track to SQLite via [dbService.addToBlacklist].
  /// 2. Adds normalized title to local cache [_blacklistedTitles].
  /// 3. Skips immediately to the next track via [handler.skipToNext].
  Future<void> dislikeCurrentTrack([dynamic track]) async {
    String? trackId;
    String? streamUrl;
    String? title;
    String? artist;

    if (track is MediaItem) {
      trackId = track.extras?['originalId']?.toString() ?? track.id;
      streamUrl = track.id;
      title = track.title;
      artist = track.artist ?? '';
    } else if (track is ScrapedTrack) {
      trackId = track.id;
      streamUrl = track.streamUrl;
      title = track.title;
      artist = track.artist;
    } else if (track is TrackEntity) {
      trackId = track.id;
      streamUrl = track.streamUrl;
      title = track.title;
      artist = track.artist;
    } else {
      final current = handler.mediaItem.value;
      if (current != null) {
        trackId = current.extras?['originalId']?.toString() ?? current.id;
        streamUrl = current.id;
        title = current.title;
        artist = current.artist ?? '';
      }
    }

    if (title != null && title.isNotEmpty) {
      final safeArtist = (artist ?? '').trim();
      await DatabaseService.instance.addToBlacklist(title, safeArtist);

      final normTitle = normalizeTitle(title);
      if (normTitle.isNotEmpty) {
        _blacklistedTitles.add(normTitle);
        _playedNormalizedTitles.add(normTitle);
      }
      final hash = getTrackHash(safeArtist, title);
      _blacklist.add(hash);
      _blacklistedTrackIds.add(hash);
      _playedTrackIds.add(hash);
    }

    if (trackId != null && trackId.isNotEmpty) {
      _blacklistedTrackIds.add(trackId);
      _playedTrackIds.add(trackId);
    }
    if (streamUrl != null && streamUrl.isNotEmpty) {
      _blacklistedTrackIds.add(streamUrl);
      _playedTrackIds.add(streamUrl);
    }

    unawaited(_persistBlacklist());
    notifyListeners();

    try {
      await handler.skipToNext();
    } catch (_) {
      // Continue silently if skip fails or queue empty
    }
  }

  /// Alias for dislikeCurrentTrack.
  Future<void> blacklistCurrentTrack([dynamic track]) =>
      dislikeCurrentTrack(track);

  /// Alias for dislikeCurrentTrack.
  Future<void> skipAndBlacklist([dynamic track]) =>
      dislikeCurrentTrack(track);

  /// Clears the persistent blacklist from memory and database.
  Future<void> clearBlacklist() async {
    _blacklist.clear();
    _blacklistedTrackIds.clear();
    _blacklistedTitles.clear();
    await dbService.clearBlacklist();
    await _persistBlacklist();
    notifyListeners();
  }

  /// Starts infinite wave strictly tailored to [genreName] using [seedQueries].
  ///
  /// - Sets [activeGenre] = genreName.
  /// - Clears queue from previous genre and resets session tracking.
  /// - Searches tracks STRICTLY by passed [seedQueries] (or favorites for 'Мой Микс').
  /// - Starts playback of first found track immediately.
  /// - Loads remaining tracks asynchronously in background.
  Future<void> startWaveForGenre(
    String genreName,
    List<String> seedQueries,
  ) async {
    activeGenre = genreName;
    _isWaveActive = true;
    _activeSeeds = List<String>.from(seedQueries);

    // Clear wave queue from previous genre and reset session tracking
    clearSessionCache();
    await handler.setQueueAndPlay(const <MediaItem>[], 0);

    _playbackSub?.cancel();
    _playbackSub = handler.playbackState.listen((_) => _checkAndRefillQueue());

    notifyListeners();

    // 1. Instant Start: Find first suitable track strictly matching queries
    final firstTrack = await _findFirstTrack(seeds: _activeSeeds);

    if (firstTrack != null && _isWaveActive) {
      await handler.setQueueAndPlay([firstTrack.toMediaItem()], 0);

      // 2. Fetch remaining 8–10 tracks in background and append
      unawaited(_fetchRemainingAndAppend(count: 10, seeds: _activeSeeds));
    } else {
      final initialTracks =
          await generateWaveTracks(count: 12, seeds: _activeSeeds);
      if (initialTracks.isNotEmpty && _isWaveActive) {
        final items = initialTracks.map((t) => t.toMediaItem()).toList();
        await handler.setQueueAndPlay(items, 0);
      }
    }
    notifyListeners();
  }

  /// Starts infinite wave mode.
  ///
  /// INSTANT PLAYBACK OPTIMIZATION:
  /// - Scrapes and finds the FIRST matching track immediately.
  /// - Passes it straight to [NCPlayerHandler.setQueueAndPlay] without waiting
  ///   for all queries to finish.
  /// - Asynchronously loads and appends the remaining 8–10 tracks in the background.
  Future<void> startWave({List<String>? seeds, bool forceRestart = false}) async {
    _isWaveActive = true;
    activeGenre = 'Мой Микс';
    _activeSeeds = seeds != null ? List<String>.from(seeds) : null;

    _playbackSub?.cancel();
    _playbackSub = handler.playbackState.listen((_) => _checkAndRefillQueue());

    if (forceRestart || handler.queueItems.isEmpty) {
      clearSessionCache();
      await handler.setQueueAndPlay(const <MediaItem>[], 0);

      // 1. Instant Start: Find first suitable track immediately
      final firstTrack = await _findFirstTrack(seeds: _activeSeeds);

      if (firstTrack != null && _isWaveActive) {
        await handler.setQueueAndPlay([firstTrack.toMediaItem()], 0);

        // 2. Fetch remaining 8–10 tracks in background and append
        unawaited(_fetchRemainingAndAppend(count: 10, seeds: _activeSeeds));
      } else {
        // Fallback: standard batch generation
        final initialTracks =
            await generateWaveTracks(count: 12, seeds: _activeSeeds);
        if (initialTracks.isNotEmpty && _isWaveActive) {
          final items = initialTracks.map((t) => t.toMediaItem()).toList();
          await handler.setQueueAndPlay(items, 0);
        }
      }
    } else {
      _recordExistingQueue();
      await _checkAndRefillQueue();
    }
    notifyListeners();
  }

  /// Finds the very first suitable track from candidate queries for instant playback.
  Future<ScrapedTrack?> _findFirstTrack({List<String>? seeds}) async {
    final queryCandidates = await _buildQueryCandidates(seeds: seeds);

    for (final query in queryCandidates) {
      if (!_isWaveActive) return null;

      try {
        final searchResults = await scraperEngine.searchAll(query);
        if (searchResults.isEmpty) continue;

        final randomized = List<ScrapedTrack>.of(searchResults)..shuffle(_random);

        for (final track in randomized) {
          if (_isTrackAlreadyPlayed(track)) continue;

          // Check artist variety
          if (_lastArtist != null) {
            final normTrackArtist = normalizeArtist(track.artist);
            final normLastArtist = normalizeArtist(_lastArtist);
            if (normTrackArtist.isNotEmpty && normTrackArtist == normLastArtist) {
              continue;
            }
          }

          _markPlayed(
            id: track.id,
            artist: track.artist,
            title: track.title,
          );
          _lastArtist = track.artist;
          return track;
        }
      } catch (_) {
        // Continue to next candidate query
      }
    }

    return null;
  }

  /// Background task that fetches [count] additional tracks and appends them to the queue.
  Future<void> _fetchRemainingAndAppend({
    required int count,
    List<String>? seeds,
  }) async {
    if (_isGenerating || !_isWaveActive) return;
    _isGenerating = true;

    try {
      final remaining =
          await generateWaveTracks(count: count, seeds: seeds);
      if (remaining.isNotEmpty && _isWaveActive) {
        final items = remaining.map((t) => t.toMediaItem()).toList();
        await handler.appendToQueue(items);
      }
    } catch (_) {
      // Best-effort; monitor will refill on next playback event
    } finally {
      _isGenerating = false;
    }
  }

  /// Stops the auto-replenishing wave monitor.
  void stopWave() {
    _isWaveActive = false;
    activeGenre = null;
    _playbackSub?.cancel();
    _playbackSub = null;
    recommendationEngine.clearHistory();
    notifyListeners();
  }

  void _recordExistingQueue() {
    for (final item in handler.queueItems) {
      _markPlayed(
        id: item.id,
        originalId: item.extras?['originalId']?.toString(),
        artist: item.artist,
        title: item.title,
      );
    }
    if (handler.queueItems.isNotEmpty) {
      _lastArtist = handler.queueItems.last.artist;
    }
  }

  void _markPlayed({
    required String id,
    String? originalId,
    String? artist,
    String? title,
  }) {
    _playedTrackIds.add(id);
    if (originalId != null && originalId.isNotEmpty) {
      _playedTrackIds.add(originalId);
    }
    if (title != null && title.isNotEmpty) {
      final normTitle = normalizeTitle(title);
      if (normTitle.isNotEmpty) {
        _playedNormalizedTitles.add(normTitle);
      }
      final hash = getTrackHash(artist, title);
      _playedTrackIds.add(hash);
      recommendationEngine.recordTrack(artist ?? '', title);
    }
  }

  bool _isTrackAlreadyPlayed(ScrapedTrack track) {
    // 1. Recommendation engine sliding window deduplicator
    if (recommendationEngine.isTrackDuplicate(track.artist, track.title)) {
      return true;
    }

    // 2. Blacklist checks (hash, streamUrl, id, title)
    final hash = getTrackHash(track.artist, track.title);
    if (_blacklist.contains(hash)) return true;
    if (_blacklistedTrackIds.contains(track.id)) return true;
    if (_blacklistedTrackIds.contains(track.streamUrl)) return true;
    if (_blacklistedTrackIds.contains(track.deduplicationKey)) return true;
    if (_blacklistedTrackIds.contains(hash)) return true;

    final normTitle = normalizeTitle(track.title);
    if (_blacklistedTitles.contains(normTitle)) return true;

    // 3. Title normalization check: reject remixes or variations of same song
    if (_playedNormalizedTitles.contains(normTitle)) return true;

    // 4. ID and key checks
    if (_playedTrackIds.contains(track.id)) return true;
    if (_playedTrackIds.contains(track.streamUrl)) return true;
    if (_playedTrackIds.contains(track.deduplicationKey)) return true;
    if (_playedTrackIds.contains(hash)) return true;

    return false;
  }

  Future<void> _checkAndRefillQueue() async {
    if (!_isWaveActive || _isGenerating) return;

    final queueLength = handler.queueItems.length;
    final currentIndex = handler.currentIndex;

    // Refill when queue has 2 or fewer remaining tracks after current position
    final tracksRemaining = queueLength - 1 - currentIndex;
    if (tracksRemaining <= 2) {
      _isGenerating = true;
      try {
        final newTracks =
            await generateWaveTracks(count: 10, seeds: _activeSeeds);
        if (newTracks.isNotEmpty && _isWaveActive) {
          final items = newTracks.map((t) => t.toMediaItem()).toList();
          await handler.appendToQueue(items);
        }
      } catch (_) {
        // Retry will naturally occur on next playback state event
      } finally {
        _isGenerating = false;
      }
    }
  }

  /// Builds prioritized candidate queries from custom seeds, favorites and genre seeds.
  Future<List<String>> _buildQueryCandidates({List<String>? seeds}) async {
    final queryCandidates = <String>[];

    // If activeGenre is set, strictly use genre seed queries (or favorite tracks for 'Мой Микс')
    if (activeGenre != null && seeds != null && seeds.isNotEmpty) {
      if (activeGenre!.contains('Мой Микс') || seeds.contains('my_mix')) {
        final favorites = await dbService.getFavoriteTracks();
        if (favorites.isNotEmpty) {
          final favQueries = favorites
              .take(12)
              .map((t) => '${t.artist} ${t.title}')
              .toList()
            ..shuffle(_random);
          queryCandidates.addAll(favQueries);
        } else {
          queryCandidates.addAll(['Synthwave', 'Phonk', 'Rock', 'Post-Punk']);
        }
      } else {
        final shuffled = List<String>.of(seeds)..shuffle(_random);
        queryCandidates.addAll(shuffled);
      }
      return queryCandidates;
    }

    // Default dynamic discovery behavior:
    // 1. Custom seeds (e.g. from Genre Hub) take top priority
    if (seeds != null && seeds.isNotEmpty) {
      final shuffledCustom = List<String>.of(seeds)..shuffle(_random);
      queryCandidates.addAll(shuffledCustom);
    }

    // 2. If library has artists in favorites/downloads, pick random artists + related tracks
    final uniqueArtists = await _extractUniqueArtists();
    if (uniqueArtists.isNotEmpty) {
      final shuffledArtists = List<String>.of(uniqueArtists)..shuffle(_random);
      final chosenArtists =
          shuffledArtists.take(min(4, shuffledArtists.length));

      for (final artist in chosenArtists) {
        final related = await _fetchRelatedQueries(artist);
        queryCandidates.addAll(related);
      }
    }

    // 3. Expand with randomized genre seeds for broad discovery and fallback
    final shuffledSeeds = List<String>.of(genreSeeds)..shuffle(_random);
    queryCandidates.addAll(shuffledSeeds);

    // Shuffle the queries so the order is always randomized
    queryCandidates.shuffle(_random);

    return queryCandidates;
  }

  /// Generates a set of 10–15 fresh recommended [ScrapedTrack]s based on
  /// user history (favorites and downloaded artists) or dynamic genre seeds.
  ///
  /// Guarantees:
  /// - Takes only 1–2 tracks per query to ensure high variety.
  /// - Avoids consecutive tracks by the same artist.
  /// - Enforces title deduplication so different remixes/edits of the same
  ///   song are never queued together.
  Future<List<ScrapedTrack>> generateWaveTracks({
    int count = 12,
    List<String>? seeds,
  }) async {
    // If not set yet, initialize _lastArtist from the existing queue
    if (_lastArtist == null && handler.queueItems.isNotEmpty) {
      _lastArtist = handler.queueItems.last.artist;
    }

    final queryCandidates = await _buildQueryCandidates(seeds: seeds);

    final resolvedTracks = <ScrapedTrack>[];
    final seenThisBatchKeys = <String>{};
    final seenThisBatchTitles = <String>{};

    // Primary pass: strictly enforce artist variety (no consecutive tracks by same artist)
    await _collectFromQueries(
      queryCandidates,
      resolvedTracks,
      seenThisBatchKeys,
      seenThisBatchTitles,
      count: count,
      allowConsecutiveArtist: false,
    );

    // Ultimate fallback: only if no tracks could be resolved at all with strict variety
    if (resolvedTracks.isEmpty) {
      await _collectFromQueries(
        queryCandidates,
        resolvedTracks,
        seenThisBatchKeys,
        seenThisBatchTitles,
        count: count,
        allowConsecutiveArtist: true,
      );
    }

    return resolvedTracks;
  }

  Future<void> _collectFromQueries(
    List<String> queryCandidates,
    List<ScrapedTrack> resolvedTracks,
    Set<String> seenThisBatchKeys,
    Set<String> seenThisBatchTitles, {
    required int count,
    required bool allowConsecutiveArtist,
  }) async {
    final maxPerQuery = (queryCandidates.length <= 3)
        ? (count / max(1, queryCandidates.length)).ceil() + 2
        : 2;

    for (final query in queryCandidates) {
      if (resolvedTracks.length >= count) break;

      try {
        final searchResults = await scraperEngine.searchAll(query);
        final randomizedResults = List<ScrapedTrack>.of(searchResults)
          ..shuffle(_random);

        int takenFromQuery = 0;

        for (final track in randomizedResults) {
          final key = track.deduplicationKey;
          final normTitle = normalizeTitle(track.title);

          // Skip if played before or seen in this batch
          if (_isTrackAlreadyPlayed(track) ||
              seenThisBatchKeys.contains(key) ||
              seenThisBatchTitles.contains(normTitle)) {
            continue;
          }

          // Artist variety: prevent two consecutive tracks from the same artist
          if (!allowConsecutiveArtist && _lastArtist != null) {
            final normTrackArtist = normalizeArtist(track.artist);
            final normLastArtist = normalizeArtist(_lastArtist);
            if (normTrackArtist.isNotEmpty &&
                normTrackArtist == normLastArtist) {
              continue;
            }
          }

          // Accept track
          seenThisBatchKeys.add(key);
          seenThisBatchTitles.add(normTitle);
          _markPlayed(
            id: track.id,
            artist: track.artist,
            title: track.title,
          );
          _lastArtist = track.artist;
          resolvedTracks.add(track);
          takenFromQuery++;

          if (takenFromQuery >= maxPerQuery) break;
          if (resolvedTracks.length >= count) break;
        }
      } catch (_) {
        // Individual query network failures continue to next query
      }
    }
  }

  /// Extracts unique artists from favorites and downloaded tracks in SQLite.
  Future<List<String>> _extractUniqueArtists() async {
    try {
      final favorites = await dbService.getFavoriteTracks();
      final downloaded = await dbService.getAllDownloadedTracks();

      final allTracks = [...favorites, ...downloaded];
      final uniqueArtists = <String>{};

      for (final track in allTracks) {
        final artist = track.artist.trim();
        if (artist.isNotEmpty &&
            artist.toLowerCase() != 'unknown artist' &&
            artist.toLowerCase() != 'неизвестный исполнитель') {
          uniqueArtists.add(artist);
        }
      }

      return uniqueArtists.toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<String>> _fetchRelatedQueries(String artist) async {
    final results = <String>[];

    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': artist,
        'entity': 'song',
        'limit': '6',
      });

      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(milliseconds: 2500));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['results'] is List) {
          for (final item in data['results'] as List) {
            if (item is Map<String, dynamic>) {
              final trackName = item['trackName'] as String?;
              final artistName = item['artistName'] as String?;
              if (trackName != null && artistName != null) {
                results.add('$artistName $trackName');
              }
            }
          }
        }
      }
    } catch (_) {
      // Fallback to searching artist directly
    }

    if (results.isEmpty) {
      results.add(artist);
    }

    return results;
  }

  @override
  void dispose() {
    if (instance == this) {
      instance = null;
    }
    stopWave();
    _httpClient.close();
    super.dispose();
  }
}
