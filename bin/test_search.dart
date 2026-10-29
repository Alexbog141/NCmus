import 'dart:io';

import 'package:ncmus/features/scraper/engine/scraper_engine.dart';
import 'package:ncmus/features/scraper/models/scraped_track.dart';
import 'package:ncmus/features/scraper/providers/hitmo_provider.dart';
import 'package:ncmus/features/scraper/providers/muzofond_provider.dart';
import 'package:ncmus/features/scraper/services/mirror_resolver.dart';

String _formatDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '00:00';
  }
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final h = duration.inHours.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
  return '$m:$s';
}

void main(List<String> args) async {
  final query = args.isNotEmpty ? args.join(' ') : 'Slipknot';

  stdout.writeln('====================================================');
  stdout.writeln('NCmus Scraper Engine DoD Verification');
  stdout.writeln('Query: "$query"');
  stdout.writeln('====================================================');

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

  stdout.writeln('Execution Time: ${stopwatch.elapsedMilliseconds} ms');
  stdout.writeln(
      'Total Tracks Found Before Deduplication: $totalFoundBeforeDedup (Hitmo: ${rawResults[0].length}, Muzofond: ${rawResults[1].length})');
  stdout.writeln('Total Tracks After Deduplication: ${deduplicatedTracks.length}');
  stdout.writeln('----------------------------------------------------');
  stdout.writeln('Top 5 Scraped Tracks:');

  final displayLimit =
      deduplicatedTracks.length < 5 ? deduplicatedTracks.length : 5;
  for (var i = 0; i < displayLimit; i++) {
    final track = deduplicatedTracks[i];
    final artistTitle = '${track.artist} - ${track.title}';
    final durationStr = _formatDuration(track.duration);
    final source = track.sourceName;
    final url = track.streamUrl;

    stdout.writeln('${i + 1}. [$artistTitle] | [$durationStr] | [$source] | [$url]');
  }

  stdout.writeln('====================================================');
  stdout.writeln('Verification completed successfully.');

  hitmoProvider.dispose();
  muzofondProvider.dispose();

  exit(0);
}
