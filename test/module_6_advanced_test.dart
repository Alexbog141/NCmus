import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';

import 'package:ncmus/features/lyrics/services/lyrics_service.dart';
import 'package:ncmus/features/integrations/discord/discord_rpc_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsService & LRC Parser Verification', () {
    late LyricsService lyricsService;

    setUp(() {
      lyricsService = LyricsService();
    });

    tearDown(() {
      lyricsService.dispose();
    });

    test('parseLrc correctly parses timestamps and sorts lines', () {
      const sampleLrc = '''
[00:12.50]Line two
[00:04.20]Line one
[01:05.123]Line three
''';

      final lines = lyricsService.parseLrc(sampleLrc);

      expect(lines.length, 3);
      expect(lines[0].text, 'Line one');
      expect(lines[0].timestamp, const Duration(seconds: 4, milliseconds: 200));

      expect(lines[1].text, 'Line two');
      expect(lines[1].timestamp, const Duration(seconds: 12, milliseconds: 500));

      expect(lines[2].text, 'Line three');
      expect(lines[2].timestamp, const Duration(minutes: 1, seconds: 5, milliseconds: 123));
    });

    test('parseLrc handles empty or malformed lines gracefully', () {
      const malformedLrc = '''
[ti:Sample Title]
[ar:Sample Artist]
[invalid timestamp] Ignore me
[00:02.00]Valid line
''';

      final lines = lyricsService.parseLrc(malformedLrc);
      expect(lines.length, 1);
      expect(lines.first.text, 'Valid line');
      expect(lines.first.timestamp, const Duration(seconds: 2));
    });
  });

  group('DiscordRpcService Verification', () {
    test('DiscordRpcService safely initializes and handles updates without crashing', () {
      final discordService = DiscordRpcService();

      // Calling initialize on test runner should never throw
      discordService.initialize();

      const testItem = MediaItem(
        id: 'test_url',
        title: 'Cyberpunk Odyssey',
        artist: 'Antigravity Synth',
        duration: Duration(minutes: 3, seconds: 45),
      );

      // Updating presence or clearing should safely catch any IPC socket errors in tests
      discordService.updatePresence(
        item: testItem,
        isPlaying: true,
        position: const Duration(seconds: 30),
      );

      discordService.updatePresence(
        item: testItem,
        isPlaying: false,
        position: const Duration(seconds: 30),
      );

      discordService.clear();
      discordService.dispose();
    });
  });
}
