import '../models/scraped_track.dart';
import '../providers/hitmo_provider.dart';
import '../providers/music_provider.dart';
import '../providers/muzofond_provider.dart';

class ScraperEngine {
  final List<MusicProvider> providers;

  const ScraperEngine({
    required this.providers,
  });

  static ScraperEngine? _instance;
  static ScraperEngine get instance {
    _instance ??= ScraperEngine(
      providers: [
        HitmoProvider(),
        MuzofondProvider(),
      ],
    );
    return _instance!;
  }

  Future<List<ScrapedTrack>> searchAll(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || providers.isEmpty) {
      return const [];
    }

    // Parallel search across all active providers
    final searchFutures = providers.map((provider) async {
      try {
        return await provider.search(trimmedQuery);
      } catch (_) {
        return <ScrapedTrack>[];
      }
    });

    final nestedResults = await Future.wait(searchFutures);

    // Aggregate into a flat list
    final List<ScrapedTrack> rawTracks = [];
    for (final trackList in nestedResults) {
      rawTracks.addAll(trackList);
    }

    // Deduplication by deduplicationKey preserving best quality / first result
    final Map<String, ScrapedTrack> deduplicated = {};

    for (final track in rawTracks) {
      final key = track.deduplicationKey;
      if (!deduplicated.containsKey(key)) {
        deduplicated[key] = track;
      } else {
        final existing = deduplicated[key]!;
        // Quality preference: prefer track with valid duration and valid cover
        final existingScore = (existing.duration > Duration.zero ? 2 : 0) +
            (existing.coverUrl != null && existing.coverUrl!.isNotEmpty ? 1 : 0);
        final candidateScore = (track.duration > Duration.zero ? 2 : 0) +
            (track.coverUrl != null && track.coverUrl!.isNotEmpty ? 1 : 0);

        if (candidateScore > existingScore) {
          deduplicated[key] = track;
        }
      }
    }

    return deduplicated.values.toList();
  }
}
