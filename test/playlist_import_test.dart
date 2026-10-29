import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/features/library/services/playlist_import_service.dart';
import 'package:ncmus/features/library/services/playlist_url_scraper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService db;
  late PlaylistImportService importService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ncmus_import_test_');
    final dbPath = p.join(tempDir.path, 'test_ncmus.db');
    db = DatabaseService.instance;
    db.setCustomPath(dbPath);
    importService = PlaylistImportService.instance;
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('PlaylistImportService Tests', () {
    test('parseRawText cleans numbers, timings, links and formats', () {
      const sampleText = '''
1. The Prodigy - Breathe (05:35)
2) Daft Punk — Get Lucky 04:08
3. https://music.yandex.ru/track/12345
Kavinsky\tNightcall
Carpenter Brut - Turbo Killer
The Prodigy - Breathe
''';

      final parsed = importService.parseRawText(sampleText);

      // Should deduplicate 'The Prodigy - Breathe'
      expect(parsed.length, 4);

      expect(parsed[0].artist, 'The Prodigy');
      expect(parsed[0].title, 'Breathe');

      expect(parsed[1].artist, 'Daft Punk');
      expect(parsed[1].title, 'Get Lucky');

      expect(parsed[2].artist, 'Kavinsky');
      expect(parsed[2].title, 'Nightcall');

      expect(parsed[3].artist, 'Carpenter Brut');
      expect(parsed[3].title, 'Turbo Killer');
    });

    test('importTracksFromText imports to SQLite and reports progress', () async {
      const sample = '''
Mick Gordon - Rip & Tear
Perturbator - Future Club
''';

      final progressCalls = <Map<String, int>>[];
      final count = await importService.importTracksFromText(
        sample,
        playlistName: 'VK Test Playlist',
        onProgress: (processed, total) {
          progressCalls.add({'processed': processed, 'total': total});
        },
      );

      expect(count, 2);
      expect(progressCalls.isNotEmpty, isTrue);
      expect(progressCalls.last['processed'], 2);
      expect(progressCalls.last['total'], 2);

      final favorites = await db.getFavoriteTracks();
      expect(favorites.length, 2);
      expect(favorites.any((t) => t.title == 'Rip & Tear'), isTrue);
      expect(favorites.any((t) => t.title == 'Future Club'), isTrue);
    });
    test('PlaylistUrlScraper.decodeHtmlBytes correctly decodes UTF-8 and CP1251', () {
      // 1. UTF-8
      final utf8Bytes = [0xD0, 0x9A, 0xD0, 0xB8, 0xD0, 0xBD, 0xD0, 0xBE]; // "Кино" in UTF-8
      expect(PlaylistUrlScraper.decodeHtmlBytes(utf8Bytes), 'Кино');

      // 2. CP1251: "Кино - Группа крови"
      // К (0xCA), и (0xE8), н (0xED), о (0xEE), ' ' (0x20), - (0x2D), ' ' (0x20),
      // Г (0xC3), р (0xF0), у (0xF3), п (0xEF), п (0xEF), а (0xE0), ' ' (0x20),
      // к (0xEA), р (0xF0), о (0xEE), в (0xE2), и (0xE8)
      final cp1251Bytes = [
        0xCA, 0xE8, 0xED, 0xEE, 0x20, 0x2D, 0x20,
        0xC3, 0xF0, 0xF3, 0xEF, 0xEF, 0xE0, 0x20,
        0xEA, 0xF0, 0xEE, 0xE2, 0xE8
      ];
      expect(PlaylistUrlScraper.decodeHtmlBytes(cp1251Bytes), 'Кино - Группа крови');
    });
  });
}

