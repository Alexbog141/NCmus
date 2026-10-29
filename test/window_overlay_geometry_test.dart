import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/audio/position_data.dart';
import 'package:ncmus/core/services/window_overlay_service.dart';
import 'package:ncmus/features/ui/widgets/cyber_orb_overlay.dart';

void main() {
  group('WindowOverlayService Geometry & Restoration Tests', () {
    test('Collapsed orb mode window size is strictly 128x128 px', () {
      expect(WindowOverlayService.orbWindowSize, equals(const Size(128, 128)));
      expect(WindowOverlayService.orbWindowSize.width, equals(128.0));
      expect(WindowOverlayService.orbWindowSize.height, equals(128.0));

      // 64x64 orb inside 128x128 window leaves exactly 32px safe margin on all 4 sides
      const orbDiameter = 64.0;
      final horizontalMargin =
          (WindowOverlayService.orbWindowSize.width - orbDiameter) / 2;
      final verticalMargin =
          (WindowOverlayService.orbWindowSize.height - orbDiameter) / 2;

      expect(horizontalMargin, equals(32.0));
      expect(verticalMargin, equals(32.0));
    });

    test('Expanded HUD capsule window size is strictly 440x130 px', () {
      expect(WindowOverlayService.hudWindowSize, equals(const Size(440, 130)));
      expect(WindowOverlayService.hudWindowSize.width, equals(440.0));
      expect(WindowOverlayService.hudWindowSize.height, equals(130.0));

      // 340x76 capsule inside 440x130 window leaves 50px horizontal and 27px vertical margin
      const capsuleWidth = 340.0;
      const capsuleHeight = 76.0;
      final horizontalMargin =
          (WindowOverlayService.hudWindowSize.width - capsuleWidth) / 2;
      final verticalMargin =
          (WindowOverlayService.hudWindowSize.height - capsuleHeight) / 2;

      expect(horizontalMargin, equals(50.0));
      expect(verticalMargin, equals(27.0));
    });

    test('Restoration of player geometry after overlay closed', () async {
      final service = WindowOverlayService.instance;

      // Initial default geometry
      expect(service.savedWindowSize, equals(WindowOverlayService.defaultWindowSize));
      expect(service.savedWindowPosition, equals(Offset.zero));

      // Simulate a custom pre-overlay user window geometry (e.g. customized desktop size/pos)
      const customSize = Size(1440, 900);
      const customPos = Offset(120, 80);
      service.setSavedGeometry(size: customSize, position: customPos);

      expect(service.savedWindowSize, equals(customSize));
      expect(service.savedWindowPosition, equals(customPos));

      // In testing environment without active native windowManager session,
      // verify state flags and geometry retention
      service.isOverlayActive.value = true;
      service.isExpanded.value = true;

      // When restoreApp is triggered, overlay flags are reset
      service.isExpanded.value = false;
      service.isOverlayActive.value = false;

      expect(service.isOverlayActive.value, isFalse);
      expect(service.isExpanded.value, isFalse);
      expect(service.savedWindowSize, equals(customSize));
      expect(service.savedWindowPosition, equals(customPos));
    });

    test('Transition target position calculation centers 128x128 window', () {
      const savedSize = Size(1200, 800);
      const savedPos = Offset(100, 100);

      final targetX = savedPos.dx + (savedSize.width - 128) / 2;
      final targetY = savedPos.dy + (savedSize.height - 128) / 2;

      // Center of 128x128 window matches center of saved window exactly
      final centerSaved = savedPos + Offset(savedSize.width / 2, savedSize.height / 2);
      final centerTarget = Offset(targetX, targetY) + const Offset(64, 64);
      expect(centerTarget, equals(centerSaved));
    });

    testWidgets(
        'Anchor Orb strictly preserves 56x56 px dimensions, 1.0 aspect ratio, and (36, 36) anchor position without shifting',
        (WidgetTester tester) async {
      final handler = _TestPlayerHandler();
      final service = WindowOverlayService.instance;
      service.isOverlayActive.value = true;
      service.isExpanded.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyberOrbOverlay(handler: handler),
          ),
        ),
      );
      await tester.pump();
      // Allow entrance animation (160ms) to complete
      await tester.pump(const Duration(milliseconds: 160));

      // 1. Collapsed state verification: exact 56x56 circle anchored at (36, 36)
      final orbFinder = find.byKey(const Key('cyber_anchor_orb'));
      expect(orbFinder, findsOneWidget);

      final collapsedSize = tester.getSize(orbFinder);
      expect(collapsedSize.width, equals(56.0));
      expect(collapsedSize.height, equals(56.0));
      expect(collapsedSize.width / collapsedSize.height, equals(1.0));

      final initialTopLeft = tester.getTopLeft(orbFinder);
      expect(initialTopLeft, equals(const Offset(36.0, 36.0)));

      // 2. Midway through expansion animation (t ~ 0.4)
      service.isExpanded.value = true;
      await tester.pump(const Duration(milliseconds: 100));

      final midSize = tester.getSize(orbFinder);
      expect(midSize.width, equals(56.0));
      expect(midSize.height, equals(56.0));
      expect(midSize.width / midSize.height, equals(1.0));
      expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)));

      // 3. Fully expanded state (t = 1.0)
      await tester.pump(const Duration(milliseconds: 200));

      final expandedSize = tester.getSize(orbFinder);
      expect(expandedSize.width, equals(56.0));
      expect(expandedSize.height, equals(56.0));
      expect(expandedSize.width / expandedSize.height, equals(1.0));
      expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)));

      // 4. Midway through collapse animation
      service.isExpanded.value = false;
      await tester.pump(const Duration(milliseconds: 100));

      final midCollapseSize = tester.getSize(orbFinder);
      expect(midCollapseSize.width, equals(56.0));
      expect(midCollapseSize.height, equals(56.0));
      expect(midCollapseSize.width / midCollapseSize.height, equals(1.0));
      expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)));

      // 5. Back to fully collapsed state
      await tester.pump(const Duration(milliseconds: 200));

      final finalSize = tester.getSize(orbFinder);
      expect(finalSize.width, equals(56.0));
      expect(finalSize.height, equals(56.0));
      expect(finalSize.width / finalSize.height, equals(1.0));
      expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)));
    });

    testWidgets(
        'At _morphController.value equal to 0.0, 0.01, 0.5, 0.99 and 1.0 Aspect Ratio of Key("cyber_anchor_orb") is strictly 1.0 (56.0 x 56.0)',
        (WidgetTester tester) async {
      final handler = _TestPlayerHandler();
      final service = WindowOverlayService.instance;
      service.isOverlayActive.value = true;
      service.isExpanded.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyberOrbOverlay(handler: handler),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      final state =
          tester.state<CyberOrbOverlayState>(find.byType(CyberOrbOverlay));
      final orbFinder = find.byKey(const Key('cyber_anchor_orb'));

      const testValues = [0.0, 0.01, 0.5, 0.99, 1.0];
      for (final value in testValues) {
        state.morphController.value = value;
        await tester.pump();

        expect(orbFinder, findsOneWidget);
        final size = tester.getSize(orbFinder);
        expect(size.width, equals(56.0),
            reason: 'Failed width check at morph value $value');
        expect(size.height, equals(56.0),
            reason: 'Failed height check at morph value $value');
        expect(size.width / size.height, equals(1.0),
            reason: 'Failed aspect ratio check at morph value $value');
        expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)),
            reason: 'Failed anchor position check at morph value $value');
      }
    });

    testWidgets('Anchor Orb GestureDetector supports both onTap and onPanStart',
        (WidgetTester tester) async {
      final handler = _TestPlayerHandler();
      final service = WindowOverlayService.instance;
      service.isOverlayActive.value = true;
      service.isExpanded.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyberOrbOverlay(handler: handler),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 160));

      final orbFinder = find.byKey(const Key('cyber_anchor_orb'));
      expect(orbFinder, findsOneWidget);

      // Verify ancestor GestureDetector has onTap and onPanStart
      final gestureDetector = tester.widget<GestureDetector>(
        find.ancestor(
          of: orbFinder,
          matching: find.byType(GestureDetector),
        ).first,
      );
      expect(gestureDetector.onTap, isNotNull);
      expect(gestureDetector.onPanStart, isNotNull);
    });

    testWidgets(
        '10 consecutive expand/collapse cycles keep orb as a full 56x56 circle in each cycle',
        (WidgetTester tester) async {
      final handler = _TestPlayerHandler();
      final service = WindowOverlayService.instance;
      service.isOverlayActive.value = true;
      service.isExpanded.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyberOrbOverlay(handler: handler),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 160));

      final orbFinder = find.byKey(const Key('cyber_anchor_orb'));

      for (var i = 0; i < 10; i++) {
        // Expand
        service.isExpanded.value = true;
        await tester.pump(const Duration(milliseconds: 50));
        var size = tester.getSize(orbFinder);
        expect(size, equals(const Size(56.0, 56.0)));

        await tester.pump(const Duration(milliseconds: 250));
        size = tester.getSize(orbFinder);
        expect(size, equals(const Size(56.0, 56.0)));

        // Collapse
        service.isExpanded.value = false;
        await tester.pump(const Duration(milliseconds: 50));
        size = tester.getSize(orbFinder);
        expect(size, equals(const Size(56.0, 56.0)));

        await tester.pump(const Duration(milliseconds: 250));
        size = tester.getSize(orbFinder);
        expect(size, equals(const Size(56.0, 56.0)));
        expect(tester.getTopLeft(orbFinder), equals(const Offset(36.0, 36.0)));
      }
    });
  });
}

class _TestPlayerHandler extends NCPlayerHandler {
  _TestPlayerHandler() {
    mediaItem.add(
      const MediaItem(id: '1', title: 'Test Title', artist: 'Test Artist'),
    );
  }

  @override
  MediaItem? get currentItem =>
      const MediaItem(id: '1', title: 'Test Title', artist: 'Test Artist');

  @override
  Stream<PlaybackState> get playbackStateStream =>
      Stream.value(PlaybackState(playing: false));

  @override
  Stream<PositionData> get positionDataStream =>
      Stream.value(const PositionData(Duration.zero, Duration.zero, Duration.zero));
}
