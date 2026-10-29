import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/features/scraper/engine/scraper_engine.dart';
import 'package:ncmus/features/scraper/models/scraped_track.dart';
import 'package:ncmus/features/scraper/providers/hitmo_provider.dart';
import 'package:ncmus/features/scraper/providers/muzofond_provider.dart';
import 'package:ncmus/features/scraper/services/mirror_resolver.dart';

void main() {
  test('NCmus Scraper Engine DoD Verification', () async {
    const query = 'Slipknot';

    final mirrorResolver = MirrorResolver();
    final hitmoProvider = HitmoProvider(mirrorResolver: mirrorResolver);
    final muzofondProvider = MuzofondProvider(mirrorResolver: mirrorResolver);

    final engine = ScraperEngine(
      providers: [
        hitmoProvider,
        muzofondProvider,
      ],
    );

    final stopwatch = Stopwatch()..start();

    final rawResults = await Future.wait([
      hitmoProvider.search(query).catchError((_) => const <ScrapedTrack>[]),
      muzofondProvider.search(query).catchError((_) => const <ScrapedTrack>[]),
    ]);
    final totalFoundBeforeDedup = rawResults[0].length + rawResults[1].length;

    final deduplicatedTracks = await engine.searchAll(query);

    stopwatch.stop();

    expect(totalFoundBeforeDedup, greaterThan(0));
    expect(deduplicatedTracks.isNotEmpty, isTrue);

    hitmoProvider.dispose();
    muzofondProvider.dispose();
  });
}
