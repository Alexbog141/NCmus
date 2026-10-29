import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ncmus/features/library/services/import_wizard_service.dart';
import 'package:ncmus/features/scraper/engine/scraper_engine.dart';
import 'package:ncmus/features/scraper/models/scraped_track.dart';
import 'package:ncmus/features/scraper/providers/music_provider.dart';

class MockMusicProvider implements MusicProvider {
  final Map<String, List<ScrapedTrack>> responses;

  MockMusicProvider(this.responses);

  @override
  String get name => 'mock';

  @override
  String get currentBaseUrl => 'https://mock.example.com';

  @override
  Future<bool> validateMirror(String baseUrl) async => true;

  @override
  Future<List<ScrapedTrack>> search(String query) async {
    return responses[query.trim()] ?? const [];
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ImportWizardService Tests', () {
    late ImportWizardService service;

    setUp(() {
      service = ImportWizardService();
      service.wipeStagingSession();
    });

    test('wipeStagingSession clears all session data', () async {
      service.parseRawInput('Artist - Title (03:15)');
      expect(service.stagedMatches.length, 1);
      await service.wipeStagingSession();
      expect(service.stagedMatches.isEmpty, true);
      expect(service.isScanning, false);
      expect(service.totalCount, 0);
    });

    test('parseRawInput parses artist, title, duration from text and sanitizes', () {
      const text = '''
The Prodigy - Breathe (05:35)
Daft Punk - One More Time 05:20
"Linkin Park" - "Numb" [mp3uk.net]
Pendulum - Watercolour (feat. Fresh) prod.by Rob [05:08]
''';
      final list = service.parseRawInput(text);
      expect(list.length, 4);
      expect(service.stagedMatches[0].originalArtist, 'The Prodigy');
      expect(service.stagedMatches[0].originalTitle, 'Breathe');
      expect(service.stagedMatches[0].originalDuration?.inSeconds, 335);

      expect(service.stagedMatches[1].originalArtist, 'Daft Punk');
      expect(service.stagedMatches[1].originalTitle, 'One More Time');
      expect(service.stagedMatches[1].originalDuration?.inSeconds, 320);

      expect(service.stagedMatches[2].originalArtist, 'Linkin Park');
      expect(service.stagedMatches[2].originalTitle, 'Numb');

      expect(service.stagedMatches[3].originalArtist, 'Pendulum');
      expect(service.stagedMatches[3].originalTitle, 'Watercolour');
      expect(service.stagedMatches[3].originalDuration?.inSeconds, 308);
    });

    test('sanitizeQuery removes promotional tags, extensions, em-dashes and quotes', () {
      expect(
        ImportWizardService.sanitizeQuery('Rauf & Faik — Детство [mp3uk.net]'),
        'Rauf & Faik Детство',
      );
      expect(
        ImportWizardService.sanitizeQuery('MiyaGi & Эндшпиль — I Got Love (feat. Рем Дигга) prod.by beats'),
        'MiyaGi & Эндшпиль I Got Love',
      );
      expect(
        ImportWizardService.sanitizeQuery('Track Name... [320kbps] (remaster.net)'),
        'Track Name',
      );
      expect(
        ImportWizardService.sanitizeQuery('«Артист» — "Название"'),
        'Артист Название',
      );
    });

    test('findBestCandidate selects candidate within <= 2s delta', () {
      const t1 = ScrapedTrack(
        id: '1',
        title: 'Song',
        artist: 'Artist',
        duration: Duration(minutes: 3, seconds: 0),
        streamUrl: 'http://1',
        sourceName: 'mock',
      );
      const t2 = ScrapedTrack(
        id: '2',
        title: 'Song',
        artist: 'Artist',
        duration: Duration(minutes: 3, seconds: 44),
        streamUrl: 'http://2',
        sourceName: 'mock',
      );

      final match = ImportWizardService.findBestCandidate(
        [t1, t2],
        const Duration(minutes: 3, seconds: 45),
      );
      expect(match?.id, '2');
    });

    test('resolveTrackWithFallbacks cascades across attempts', () async {
      const targetTrack = ScrapedTrack(
        id: 'found_via_primary_artist',
        title: 'Wildfire',
        artist: 'SBTRKT',
        duration: Duration(minutes: 3, seconds: 20),
        streamUrl: 'http://stream',
        sourceName: 'mock',
      );

      // Provider only responds when querying primary artist
      final mockProvider = MockMusicProvider({
        'SBTRKT Wildfire': [targetTrack],
      });
      final engine = ScraperEngine(providers: [mockProvider]);

      // Query with multiple artists: "SBTRKT, Little Dragon"
      final result = await service.resolveTrackWithFallbacks(
        'SBTRKT, Little Dragon',
        'Wildfire [mp3uk.net]',
        expectedDuration: const Duration(minutes: 3, seconds: 21),
        scraperEngine: engine,
      );

      expect(result, isNotNull);
      expect(result?.id, 'found_via_primary_artist');
    });

    test('resolveDispute updates candidate and marks as exactMatch', () {
      service.parseRawInput('Muzzy - Endgame (04:12)');
      final match = service.stagedMatches.first;
      expect(match.status, ImportMatchStatus.pending);

      const candidate = ScrapedTrack(
        id: 'muzzy_endgame',
        title: 'Endgame',
        artist: 'Muzzy',
        duration: Duration(minutes: 4, seconds: 12),
        streamUrl: 'https://example.com/audio.mp3',
        sourceName: 'vk',
      );

      service.resolveDispute(match.id, candidate);
      expect(service.stagedMatches.first.status, ImportMatchStatus.exactMatch);
      expect(service.stagedMatches.first.candidate?.id, 'muzzy_endgame');
      expect(service.exactCount, 1);
      expect(service.disputedCount, 0);
    });

    test('generateMissingTracksReport generates formatted report', () {
      service.parseRawInput('Rare Artist - Underground Gem\nAnother - Obscure Track');
      service.stagedMatches[0].status = ImportMatchStatus.notFound;
      service.stagedMatches[1].status = ImportMatchStatus.notFound;

      final report = service.generateMissingTracksReport();
      expect(report.contains('NCMUS MISSING TRACKS EXPORT'), true);
      expect(report.contains('Rare Artist - Underground Gem'), true);
      expect(report.contains('Another - Obscure Track'), true);
    });
  });
}
