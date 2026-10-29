import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/services/discord_rpc_service.dart';

void main() {
  group('DiscordRpcService Presence & Timestamps Tests', () {
    late DiscordRpcService rpcService;

    setUp(() {
      rpcService = DiscordRpcService();
    });

    tearDown(() {
      rpcService.dispose();
    });

    test('buildPresenceData generates accurate fields for playing track', () {
      final fixedTime = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      const position = Duration(seconds: 45);
      const duration = Duration(minutes: 3, seconds: 30); // 210s = 210000ms

      final presence = rpcService.buildPresenceData(
        title: 'Cyberpunk City',
        artist: 'Antigravity Synth',
        isPlaying: true,
        position: position,
        duration: duration,
        currentTime: fixedTime,
      );

      expect(presence.details, 'Cyberpunk City');
      expect(presence.state, 'Antigravity Synth');
      expect(presence.largeImageKey, 'ncmus_logo');
      expect(presence.largeImageText, 'NCmus · Cyber Audio');
      expect(presence.smallImageKey, 'play');
      expect(presence.smallImageText, 'Воспроизведение');

      // startTime = now - position = 1700000000000 - 45000 = 1699999955000
      expect(presence.startTimeStamp, 1699999955000);
      expect(presence.startTime, 1699999955000);

      // endTime = startTime + duration = 1699999955000 + 210000 = 1700000165000
      expect(presence.endTimeStamp, 1700000165000);
      expect(presence.endTime, 1700000165000);
    });

    test('buildPresenceData sets small image and clears timestamps when paused', () {
      final fixedTime = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      final presence = rpcService.buildPresenceData(
        title: 'Neon Odyssey',
        artist: 'Retro Wave',
        isPlaying: false,
        position: const Duration(seconds: 20),
        duration: const Duration(minutes: 4),
        currentTime: fixedTime,
      );

      expect(presence.details, 'Neon Odyssey');
      expect(presence.state, 'Retro Wave');
      expect(presence.smallImageKey, 'pause');
      expect(presence.smallImageText, 'Пауза');
      expect(presence.startTimeStamp, isNull);
      expect(presence.endTimeStamp, isNull);
    });

    test('updatePresence and clear update lastPresence state correctly', () {
      rpcService.updatePresence(
        title: 'Test Song',
        artist: 'Test Artist',
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 2),
      );

      expect(rpcService.lastPresence, isNotNull);
      expect(rpcService.lastPresence!.details, 'Test Song');
      expect(rpcService.lastPresence!.state, 'Test Artist');

      rpcService.clear();
      expect(rpcService.lastPresence, isNull);
    });

    test('buildPresenceData truncates very long titles and artists safely', () {
      final longTitle = 'A' * 200;
      final longArtist = 'B' * 200;

      final presence = rpcService.buildPresenceData(
        title: longTitle,
        artist: longArtist,
        isPlaying: true,
      );

      expect(presence.details.length, lessThanOrEqualTo(128));
      expect(presence.details.endsWith('...'), isTrue);
      expect(presence.state.length, lessThanOrEqualTo(128));
      expect(presence.state.endsWith('...'), isTrue);
    });
  });
}
