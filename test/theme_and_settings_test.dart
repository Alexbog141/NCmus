import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncmus/core/database/database_service.dart';
import 'package:ncmus/core/theme/cyberpunk_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('AppThemePreset & ThemeController Tests', () {
    setUp(() {
      DatabaseService.instance.setCustomPath(inMemoryDatabasePath);
    });

    tearDown(() async {
      await DatabaseService.instance.close();
      DatabaseService.instance.setCustomPath(null);
    });

    test('All 5 required theme presets are defined with correct colors', () {
      const presets = AppThemePreset.presets;
      expect(presets.length, 5);

      // 1. Cyber Core
      final cyberCore = presets.firstWhere((p) => p.id == 'cyber_core');
      expect(cyberCore.primaryColor, const Color(0xFF00F0FF));
      expect(cyberCore.secondaryColor, const Color(0xFF9D4EDD));
      expect(cyberCore.backgroundColor, const Color(0xFF07080C));

      // 2. Matrix Protocol
      final matrix = presets.firstWhere((p) => p.id == 'matrix_protocol');
      expect(matrix.primaryColor, const Color(0xFF00FF66));
      expect(matrix.secondaryColor, const Color(0xFF0A2012));
      expect(matrix.backgroundColor, const Color(0xFF050B07));

      // 3. Sunset Synth
      final sunset = presets.firstWhere((p) => p.id == 'sunset_synth');
      expect(sunset.primaryColor, const Color(0xFFFF007F));
      expect(sunset.secondaryColor, const Color(0xFFFF8800));
      expect(sunset.backgroundColor, const Color(0xFF0C0614));

      // 4. Tokyo Crimson
      final tokyo = presets.firstWhere((p) => p.id == 'tokyo_crimson');
      expect(tokyo.primaryColor, const Color(0xFFFF003C));
      expect(tokyo.secondaryColor, const Color(0xFFE0E0E0));
      expect(tokyo.backgroundColor, const Color(0xFF0F0A0C));

      // 5. Cold Ice
      final coldIce = presets.firstWhere((p) => p.id == 'cold_ice');
      expect(coldIce.primaryColor, const Color(0xFF50E3C2));
      expect(coldIce.secondaryColor, const Color(0xFF1E293B));
      expect(coldIce.backgroundColor, const Color(0xFF060A12));
    });

    test('ThemeController saves and restores theme preset from SQLite', () async {
      final matrixPreset =
          AppThemePreset.presets.firstWhere((p) => p.id == 'matrix_protocol');

      // Set preset
      await ThemeController.setPreset(matrixPreset);
      expect(ThemeController.current.id, 'matrix_protocol');

      // Check SQLite sync_meta value
      final storedTheme =
          await DatabaseService.instance.getSyncMeta('app_theme');
      expect(storedTheme, 'matrix_protocol');

      // Reset in memory to default
      ThemeController.currentPreset.value = AppThemePreset.presets[0];
      expect(ThemeController.current.id, 'cyber_core');

      // Call init() to restore from SQLite
      await ThemeController.init();
      expect(ThemeController.current.id, 'matrix_protocol');
    });

    test('Wave blacklist persists in sync_meta SQLite table', () async {
      final hashes = ['artist 1 - song 1', 'artist 2 - song 2'];
      await DatabaseService.instance.setSyncMeta(
        'wave_blacklist',
        jsonEncode(hashes),
      );

      final read =
          await DatabaseService.instance.getSyncMeta('wave_blacklist');
      expect(read, isNotNull);
      final decoded = jsonDecode(read!) as List;
      expect(decoded.length, 2);
      expect(decoded.contains('artist 1 - song 1'), isTrue);
    });
  });
}
