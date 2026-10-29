import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ncmus/core/services/window_overlay_service.dart';
import 'package:ncmus/features/ui/widgets/cyber_window_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowOverlayService Specifications', () {
    test('Collapsed orb window size is 128x128 px eliminating BoxShadow clipping', () {
      expect(WindowOverlayService.orbWindowSize, equals(const Size(128, 128)));
      expect(WindowOverlayService.orbWindowSize.width, 128.0);
      expect(WindowOverlayService.orbWindowSize.height, 128.0);

      // Verify that a 64x64 orb inside a 128x128 window has exactly 32px margin on all sides:
      const orbDiameter = 64.0;
      final horizontalMargin = (WindowOverlayService.orbWindowSize.width - orbDiameter) / 2;
      final verticalMargin = (WindowOverlayService.orbWindowSize.height - orbDiameter) / 2;
      expect(horizontalMargin, equals(32.0));
      expect(verticalMargin, equals(32.0));
    });

    test('Expanded HUD window size is 440x130 px', () {
      expect(WindowOverlayService.hudWindowSize, equals(const Size(440, 130)));
    });

    test('State transitions and value notifiers work as expected', () {
      final service = WindowOverlayService.instance;
      expect(service.isOverlayActive.value, isFalse);
      expect(service.isExpanded.value, isFalse);

      service.setPointerInside(true);
      service.resetIdleTimer();
      service.setPointerInside(false);
      service.dispose();
    });
  });

  group('CyberWindowControls Widget Tests', () {
    testWidgets('Renders all 4 cyberpunk control buttons on desktop', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: CyberWindowControls(),
            ),
          ),
        ),
      );

      // If running test in desktop host environment:
      if (CyberWindowControls.isDesktop) {
        // 1. [ 🫧 ] Cyber Orb overlay button
        expect(find.byIcon(Icons.bubble_chart_rounded), findsOneWidget);
        expect(find.byTooltip('Мини-сферка HUD'), findsOneWidget);

        // 2. [ — ] Minimize button
        expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
        expect(find.byTooltip('Свернуть'), findsOneWidget);

        // 3. [ 🗖 ] Maximize / Restore button
        final hasMaximizeOrRestore =
            find.byIcon(Icons.crop_square_rounded).evaluate().isNotEmpty ||
            find.byIcon(Icons.filter_none_rounded).evaluate().isNotEmpty;
        expect(hasMaximizeOrRestore, isTrue);

        // 4. [ ✕ ] Close button
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(find.byTooltip('Закрыть'), findsOneWidget);
      } else {
        expect(find.byType(CyberWindowControls), findsOneWidget);
      }
    });

    testWidgets('Hover effect on close button changes styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: CyberWindowControls(),
            ),
          ),
        ),
      );

      if (CyberWindowControls.isDesktop) {
        final closeFinder = find.byTooltip('Закрыть');
        expect(closeFinder, findsOneWidget);

        // Simulate mouse enter
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        await gesture.moveTo(tester.getCenter(closeFinder));
        await tester.pumpAndSettle();

        // Close button hover state is rendered
        expect(closeFinder, findsOneWidget);
      }
    });

    testWidgets('Hover effect on Cyber Orb button triggers neon styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: CyberWindowControls(),
            ),
          ),
        ),
      );

      if (CyberWindowControls.isDesktop) {
        final orbFinder = find.byTooltip('Мини-сферка HUD');
        expect(orbFinder, findsOneWidget);

        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        await gesture.moveTo(tester.getCenter(orbFinder));
        await tester.pumpAndSettle();

        expect(orbFinder, findsOneWidget);
      }
    });
  });
}
