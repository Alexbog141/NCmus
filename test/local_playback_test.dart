import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/audio/local_file_audio_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testAudioFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ncmus_playback_test_');
    // Create a dummy file with Cyrillic characters in the filename:
    testAudioFile = File('${tempDir.path}/Король и Шут - Кукла колдуна.mp3');
    // Write 2048 bytes of dummy MP3 header/content
    testAudioFile.writeAsBytesSync(List.generate(2048, (i) => i % 256));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('LocalFileAudioSource correctly streams byte ranges from Cyrillic file path', () async {
    const mediaItem = MediaItem(
      id: 'local-test-1',
      title: 'Кукла колдуна',
      artist: 'Король и Шут',
    );

    final source = LocalFileAudioSource(testAudioFile, tag: mediaItem);
    expect(source.file.existsSync(), isTrue);
    expect(source.tag, equals(mediaItem));

    // Request full stream
    final fullResponse = await source.request();
    expect(fullResponse.sourceLength, equals(2048));
    expect(fullResponse.contentLength, equals(2048));
    expect(fullResponse.offset, equals(0));
    expect(fullResponse.rangeRequestsSupported, isTrue);
    expect(fullResponse.contentType, equals('audio/mpeg'));

    final fullBytes = await fullResponse.stream.expand((c) => c).toList();
    expect(fullBytes.length, equals(2048));

    // Request partial byte range (e.g. seeking)
    final partialResponse = await source.request(512, 1024);
    expect(partialResponse.sourceLength, equals(2048));
    expect(partialResponse.contentLength, equals(512));
    expect(partialResponse.offset, equals(512));

    final partialBytes = await partialResponse.stream.expand((c) => c).toList();
    expect(partialBytes.length, equals(512));
    expect(partialBytes[0], equals(fullBytes[512]));
  });
}
