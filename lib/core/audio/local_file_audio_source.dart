// ignore_for_file: experimental_member_use
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

/// A robust audio source that serves local audio files via [StreamAudioSource].
///
/// This resolves OS-level media decoding and URI path encoding issues (such as
/// Windows Media Foundation failing on percent-encoded Cyrillic/non-ASCII characters
/// or path separators) by streaming chunks directly through just_audio's localhost proxy.
class LocalFileAudioSource extends StreamAudioSource {
  final File file;

  LocalFileAudioSource(this.file, {super.tag});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final length = await file.length();
    final effectiveStart = start ?? 0;
    final effectiveEnd = end ?? length;

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: length,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      stream: file.openRead(effectiveStart, effectiveEnd),
      contentType: _resolveContentType(file.path),
    );
  }

  static String _resolveContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.aac':
        return 'audio/mp4';
      case '.wav':
        return 'audio/wav';
      case '.ogg':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }
}
