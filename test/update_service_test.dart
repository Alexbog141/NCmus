import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/services/update_service.dart';

void main() {
  group('UpdateService.normalizeVersion', () {
    test('strips a leading v and whitespace', () {
      expect(UpdateService.normalizeVersion(' v1.0.4 '), '1.0.4');
      expect(UpdateService.normalizeVersion('V2.3.0'), '2.3.0');
    });
  });

  group('UpdateService.isNewerVersion', () {
    test('detects a newer semantic version', () {
      expect(UpdateService.isNewerVersion('1.0.3+3', '1.0.4'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.9+9', '1.1.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.9.9', '2.0.0'), isTrue);
    });

    test('does not report equal or older versions', () {
      expect(UpdateService.isNewerVersion('1.0.4+4', '1.0.4'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.4+4', '1.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isFalse);
    });

    test('compares explicit build metadata', () {
      expect(UpdateService.isNewerVersion('1.0.4+4', '1.0.4+5'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.4+5', '1.0.4+4'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.4+5', '1.0.4+5'), isFalse);
    });

    test('treats malformed remote tags as not newer', () {
      expect(UpdateService.isNewerVersion('1.0.4', 'latest'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.4', ''), isFalse);
    });
  });
}
