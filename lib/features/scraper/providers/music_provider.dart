import '../models/scraped_track.dart';

abstract class MusicProvider {
  String get name;
  String get currentBaseUrl;
  Future<List<ScrapedTrack>> search(String query);
  Future<bool> validateMirror(String baseUrl);
}
