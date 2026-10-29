import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ncmus/core/audio/audio_player_handler.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/core/theme/cyberpunk_theme.dart';
import 'package:ncmus/features/ui/screens/home_shell.dart';
import 'package:ncmus/features/ui/screens/library_screen.dart';
import 'package:ncmus/features/ui/screens/playlist_detail_screen.dart';
import 'package:ncmus/features/ui/screens/sync_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ncmus_ui_test_');
    DatabaseService.instance.setCustomPath(p.join(tempDir.path, 'test_ui.db'));
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('CyberpunkTheme & GlassContainer Verification', () {
    test('CyberpunkTheme palette constants match specifications', () {
      expect(CyberpunkTheme.backgroundColor, const Color(0xFF07080C));
      expect(CyberpunkTheme.surfaceColor, const Color(0xFF0D111A));
      expect(CyberpunkTheme.neonCyan, const Color(0xFF00F0FF));
      expect(CyberpunkTheme.electricViolet, const Color(0xFF9D4EDD));
      expect(CyberpunkTheme.neonPurple, const Color(0xFF9D4EDD));
      expect(CyberpunkTheme.darkTheme.scaffoldBackgroundColor,
          CyberpunkTheme.backgroundColor);
    });

    testWidgets('GlassContainer renders with backdrop filter and child',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: const Scaffold(
            body: GlassContainer(
              child: Text('Cyberpunk Glass Text'),
            ),
          ),
        ),
      );

      expect(find.text('Cyberpunk Glass Text'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('SyncScreen Widget Tests', () {
    testWidgets('SyncScreen renders revision metrics and input fields',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: const Scaffold(
            body: SyncScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CLOUD REVISION SYNC'), findsOneWidget);
      expect(find.text('ТЕКУЩИЙ СТАТУС РЕВИЗИИ'), findsOneWidget);
      expect(find.text('СИНХРОНИЗИРОВАТЬ СЕЙЧАС'), findsOneWidget);
      expect(find.text('Local Version'), findsOneWidget);
      expect(find.text('Remote Version'), findsOneWidget);
    });
  });

  group('LibraryScreen Widget Tests', () {
    testWidgets('LibraryScreen renders tabs for Downloads and Favorites',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final handler = NCPlayerHandler();
      addTearDown(() => handler.dispose());

      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: Scaffold(
            body: LibraryScreen(handler: handler),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.textContaining('Загрузки'), findsOneWidget);
      expect(find.textContaining('Избранное'), findsOneWidget);

      // Verify tapping on 'Топ артистов' smoothly switches tab
      final topArtistsTab = find.textContaining('Топ артистов');
      expect(topArtistsTab, findsOneWidget);
      await tester.ensureVisible(topArtistsTab);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(topArtistsTab);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('LibraryScreen opens playlist as an inner layer with compact width',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final handler = NCPlayerHandler();
      addTearDown(() => handler.dispose());

      // Create test playlist
      await DatabaseService.instance.createPlaylist(
        'Cyberpunk Hits',
        description: 'Best synth tracks',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: Scaffold(
            body: LibraryScreen(handler: handler),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Playlists tab
      final playlistsTab = find.textContaining('Плейлисты');
      expect(playlistsTab, findsOneWidget);
      await tester.ensureVisible(playlistsTab);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(playlistsTab);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on playlist card
      final playlistCard = find.text('Cyberpunk Hits');
      expect(playlistCard, findsOneWidget);
      await tester.tap(playlistCard);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify PlaylistDetailScreen is rendered inside ConstrainedBox with maxWidth: 820
      expect(find.byType(PlaylistDetailScreen), findsOneWidget);
      final constrainedBoxFinder = find.ancestor(
        of: find.byType(PlaylistDetailScreen),
        matching: find.byType(ConstrainedBox),
      );
      expect(constrainedBoxFinder, findsWidgets);
      final constrainedBox = tester.widget<ConstrainedBox>(constrainedBoxFinder.first);
      expect(constrainedBox.constraints.maxWidth, 820.0);

      // Close playlist via close icon button
      final closeButton = find.byTooltip('Закрыть');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify PlaylistDetailScreen is dismissed
      expect(find.byType(PlaylistDetailScreen), findsNothing);
    });
  });

  group('HomeShell Adaptive Layout Tests', () {
    testWidgets('Wide screen (> 720) displays desktop Sidebar navigation',
        (tester) async {
      final handler = NCPlayerHandler();
      addTearDown(() => handler.dispose());

      // Configure wide screen (1024x768)
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: HomeShell(handler: handler),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NCMUS'), findsOneWidget);
      expect(find.text('CYBER CORE'), findsOneWidget);
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Поиск треков'), findsOneWidget);
      expect(find.text('Медиатека'), findsOneWidget);
      expect(find.text('Синхронизация'), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);
      expect(find.text('LOCAL-FIRST'), findsOneWidget);
    });

    testWidgets('Mobile screen (<= 720) displays mobile BottomNavigationBar with 5 tabs',
        (tester) async {
      final handler = NCPlayerHandler();
      addTearDown(() => handler.dispose());

      // Configure mobile screen (400x800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: CyberpunkTheme.darkTheme,
          home: HomeShell(handler: handler),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // On mobile, BottomNavigationBar has 5 tabs
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Поиск'), findsOneWidget);
      expect(find.text('Медиатека'), findsOneWidget);
      expect(find.text('Синхронизация'), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);
    });
  });
}
