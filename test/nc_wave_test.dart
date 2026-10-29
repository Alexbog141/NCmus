import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/scraper/engine/scraper_engine.dart';
import 'package:ncmus/features/scraper/models/scraped_track.dart';
import 'package:ncmus/features/scraper/providers/music_provider.dart';
import 'package:ncmus/features/storage/models/track_entity.dart';
import 'package:ncmus/features/wave/services/nc_wave_service.dart';

class MockMusicProvider implements MusicProvider {
  int callCount = 0;
  final List<ScrapedTrack> Function(String query, int callIndex) onSearch;

  MockMusicProvider(this.onSearch);

  @override
  String get name => 'MockProvider';

  @override
  String get currentBaseUrl => 'https://mock.music';

  @override
  Future<List<ScrapedTrack>> search(String query) async {
    callCount++;
    return onSearch(query, callCount);
  }

  @override
  Future<bool> validateMirror(String baseUrl) async => true;
}

class FakePlayerHandler extends NCPlayerHandler {
  final List<MediaItem> _fakeQueue = [];
  int _fakeIndex = 0;
  bool skipToNextCalled = false;

  @override
  List<MediaItem> get queueItems => List.unmodifiable(_fakeQueue);

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
  Future<void> skipToNext() async {
    skipToNextCalled = true;
    if (_fakeIndex < _fakeQueue.length - 1) {
      _fakeIndex++;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NCWaveService Title Normalization & Deduplication Tests', () {
    test('normalizeTitle strips remixes, slowed, feat, brackets, and extra spaces', () {
      expect(NCWaveService.normalizeTitle('Просто отпускай'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай (Remix)'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай [slowed + reverb]'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай (bass boosted)'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай (feat. Mary)'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай (Radio Edit)'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Просто отпускай - Speed Up'), 'просто отпускай');
      expect(NCWaveService.normalizeTitle('Numb (feat. Jay-Z) [Live]'), 'numb');
    });

    test('genreSeeds contains all required genres', () {
      final requiredSeeds = [
        'Post-Punk',
        'Cyberpunk',
        'Synthwave',
        'Phonk',
        'Rock',
        'Alternative',
        'Indie',
        'Electronic',
        'Nu Metal',
      ];
      for (final seed in requiredSeeds) {
        expect(NCWaveService.genreSeeds, contains(seed));
      }
    });

    test('drops duplicate versions and remixes of the same song in wave queue', () async {
      final handler = FakePlayerHandler();

      // Start queue with the original track
      handler.setQueueAndPlay([
        const MediaItem(
          id: 'url_orig',
          title: 'Просто отпускай',
          artist: 'Инсомния',
          extras: {'originalId': 'id_orig'},
        ),
      ], 0);

      final provider = MockMusicProvider((query, callIndex) {
        return [
          // Remix of already queued song -> MUST be dropped!
          const ScrapedTrack(
            id: 'id_remix',
            title: 'Просто отпускай (Remix)',
            artist: 'Инсомния',
            duration: Duration(minutes: 3),
            streamUrl: 'https://stream.mock/remix.mp3',
            sourceName: 'Mock',
          ),
          // Slowed version of already queued song -> MUST be dropped!
          const ScrapedTrack(
            id: 'id_slowed',
            title: 'Просто отпускай [slowed + reverb]',
            artist: 'Инсомния',
            duration: Duration(minutes: 3),
            streamUrl: 'https://stream.mock/slowed.mp3',
            sourceName: 'Mock',
          ),
          // Completely fresh song -> MUST be accepted!
          const ScrapedTrack(
            id: 'id_fresh_unique',
            title: 'В темноте',
            artist: 'Другой Артист',
            duration: Duration(minutes: 3),
            streamUrl: 'https://stream.mock/unique.mp3',
            sourceName: 'Mock',
          ),
        ];
      });

      final scraper = ScraperEngine(providers: [provider]);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
      );

      // Start wave: records 'просто отпускай' into _playedNormalizedTitles
      await waveService.startWave();

      expect(waveService.playedNormalizedTitles, contains('просто отпускай'));

      // Check auto-refilled tracks: only the fresh song must be in queue
      final addedItems = handler.queueItems.skip(1).toList();
      for (final item in addedItems) {
        expect(
          NCWaveService.normalizeTitle(item.title),
          isNot(equals('просто отпускай')),
          reason: 'No remix or variation of «Просто отпускай» should ever be added',
        );
      }
      expect(handler.queueItems.any((t) => t.id == 'https://stream.mock/unique.mp3'), isTrue);

      waveService.stopWave();
      waveService.dispose();
    });

    test('artist variety: does not add two consecutive tracks by the same artist', () async {
      final handler = FakePlayerHandler();
      handler.setQueueAndPlay([
        const MediaItem(
          id: 'url_1',
          title: 'Track A',
          artist: 'Perturbator',
        ),
      ], 0);

      int queryCount = 0;
      final provider = MockMusicProvider((query, callIndex) {
        queryCount++;
        if (queryCount.isOdd) {
          // Returns tracks by Perturbator (same as last artist in queue)
          return [
            ScrapedTrack(
              id: 'pert_$queryCount',
              title: 'Pert Song $queryCount',
              artist: 'Perturbator',
              duration: const Duration(minutes: 3),
              streamUrl: 'https://pert.mock/$queryCount.mp3',
              sourceName: 'Mock',
            ),
          ];
        } else {
          // Returns tracks by Carpenter Brut (different artist)
          return [
            ScrapedTrack(
              id: 'carp_$queryCount',
              title: 'Brut Song $queryCount',
              artist: 'Carpenter Brut',
              duration: const Duration(minutes: 3),
              streamUrl: 'https://carp.mock/$queryCount.mp3',
              sourceName: 'Mock',
            ),
          ];
        }
      });

      final scraper = ScraperEngine(providers: [provider]);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
      );

      // Generating tracks when last artist is 'Perturbator':
      final generated = await waveService.generateWaveTracks(count: 2);
      expect(generated.isNotEmpty, isTrue);

      // The very first track generated must NOT be Perturbator
      expect(
        NCWaveService.normalizeArtist(generated.first.artist),
        isNot(equals(NCWaveService.normalizeArtist('Perturbator'))),
        reason: 'Consecutive tracks by the same artist must be avoided',
      );

      waveService.dispose();
    });

    test('blacklistCurrentTrack skips track and prevents it and its remixes from playing', () async {
      final handler = FakePlayerHandler();
      const scraper = ScraperEngine(providers: []);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
      );

      final dislikedTrack = TrackEntity(
        id: 'bad_track_1',
        title: 'Ужасная песня (Bass Boosted)',
        artist: 'Плохой Артист',
        duration: const Duration(minutes: 3),
        streamUrl: 'https://bad.mock/song.mp3',
        sourceName: 'Mock',
        createdAt: DateTime.now(),
      );

      await waveService.blacklistCurrentTrack(dislikedTrack);

      expect(handler.skipToNextCalled, isTrue);
      expect(waveService.blacklistedTrackIds, contains('bad_track_1'));
      expect(waveService.blacklistedTrackIds, contains('https://bad.mock/song.mp3'));
      expect(waveService.blacklistedTitles, contains('ужасная песня'));

      // Now verify that any remix or variation of the blacklisted title is rejected
      const candidateRemix = ScrapedTrack(
        id: 'different_id_999',
        title: 'Ужасная песня [Radio Edit]',
        artist: 'Плохой Артист',
        duration: Duration(minutes: 3),
        streamUrl: 'https://different.mock/remix.mp3',
        sourceName: 'Mock',
      );

      final nextBatch = await waveService.generateWaveTracks(count: 1);
      // Candidate remix cannot be in nextBatch
      expect(nextBatch.any((t) => t.id == candidateRemix.id), isFalse);

      waveService.dispose();
    });

    test('dislikeCurrentTrack writes to SQLite blacklist table and updates cache', () async {
      final db = DatabaseService.instance;
      final handler = FakePlayerHandler();
      const scraper = ScraperEngine(providers: []);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
        dbService: db,
      );

      final track = TrackEntity(
        id: 'disliked_track_sqlite',
        title: 'Ужасный Трек (Speed Up Remix)',
        artist: 'Анонимный Исполнитель',
        duration: const Duration(minutes: 2),
        streamUrl: 'https://dislike.mock/stream.mp3',
        sourceName: 'Mock',
        createdAt: DateTime.now(),
      );

      await waveService.dislikeCurrentTrack(track);

      expect(handler.skipToNextCalled, isTrue);
      expect(waveService.blacklistedTitles, contains('ужасный трек'));

      // Check SQLite table directly
      final isBanned = await db.isBlacklisted('Ужасный Трек [Slowed]', 'Анонимный Исполнитель');
      expect(isBanned, isTrue);

      final allBanned = await db.getBlacklistedNormalizedTitles();
      expect(allBanned, contains('ужасный трек'));

      waveService.dispose();
    });

    test('dislikeCurrentTrack with MediaItem writes to DatabaseService and logs sync_outbox', () async {
      final db = DatabaseService.instance;
      final handler = FakePlayerHandler();
      const scraper = ScraperEngine(providers: []);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
        dbService: db,
      );

      const item = MediaItem(
        id: 'https://dislike.mock/media_item.mp3',
        title: 'Toxic Song (Remix)',
        artist: 'Toxic Artist',
        extras: {'originalId': 'orig_toxic_123'},
      );

      await waveService.dislikeCurrentTrack(item);

      expect(handler.skipToNextCalled, isTrue);
      expect(waveService.blacklistedTitles, contains('toxic song'));

      final isBanned = await db.isBlacklisted('Toxic Song', 'Toxic Artist');
      expect(isBanned, isTrue);

      final outbox = await db.getOutboxEntries();
      final hasDislikeAction = outbox.any((e) =>
          e['action'] == 'blacklist_add' &&
          (jsonDecode(e['payload'] as String)['title'] == 'Toxic Song (Remix)'));
      expect(hasDislikeAction, isTrue);

      waveService.dispose();
    });

    test('startWaveForGenre sets activeGenre and searches strictly by genre seeds', () async {
      final handler = FakePlayerHandler();
      final provider = MockMusicProvider((query, callIndex) {
        if (query.contains('Phonk')) {
          return [
            const ScrapedTrack(
              id: 'phonk_track_1',
              title: 'Tokyo Drift Phonk',
              artist: 'Kordhell',
              duration: Duration(minutes: 2),
              streamUrl: 'https://phonk.mock/1.mp3',
              sourceName: 'Mock',
            ),
          ];
        }
        return [];
      });

      final scraper = ScraperEngine(providers: [provider]);
      final waveService = NCWaveService(
        handler: handler,
        scraperEngine: scraper,
      );

      await waveService.startWaveForGenre('Фонк', ['Phonk', 'Drift Phonk']);

      expect(waveService.activeGenre, 'Фонк');
      expect(waveService.isWaveActive, isTrue);
      expect(handler.queueItems.isNotEmpty, isTrue);
      expect(handler.queueItems.first.title, 'Tokyo Drift Phonk');

      waveService.stopWave();
      expect(waveService.activeGenre, isNull);
      expect(waveService.isWaveActive, isFalse);

      waveService.dispose();
    });
  });
}

