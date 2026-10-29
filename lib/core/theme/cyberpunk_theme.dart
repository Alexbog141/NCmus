import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../database/database_service.dart';

/// Dynamic theme palette for NCmus.
class AppColors {
  final Color bgPrimary;
  final Color bgSurface;
  final Color cardGlass;
  final Color neonPrimary;
  final Color neonSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color neonPink;
  final Color neonGreen;
  final Color neonAmber;

  const AppColors({
    required this.bgPrimary,
    required this.bgSurface,
    required this.cardGlass,
    required this.neonPrimary,
    required this.neonSecondary,
    this.textPrimary = const Color(0xFFF5F7FF),
    this.textSecondary = const Color(0xB3C6CDE0),
    this.textMuted = const Color(0x7AA6AEC4),
    this.neonPink = const Color(0xFFE4588A),
    this.neonGreen = const Color(0xFF4ADE80),
    this.neonAmber = const Color(0xFFF4B860),
  });

  LinearGradient get primarySecondaryGradient => LinearGradient(
        colors: [neonPrimary, neonSecondary],
        stops: const [0.0, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get secondaryPrimaryGradient => LinearGradient(
        colors: [neonSecondary, neonPrimary],
        stops: const [0.0, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get glassBorderGradient => LinearGradient(
        colors: [
          neonPrimary.withValues(alpha: 0.42),
          const Color(0x24FFFFFF),
          neonSecondary.withValues(alpha: 0.28),
        ],
        stops: const [0.0, 0.48, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get glassBorderGradientSoft => LinearGradient(
        colors: [
          const Color(0x3DFFFFFF),
          neonPrimary.withValues(alpha: 0.08),
          neonSecondary.withValues(alpha: 0.16),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get backgroundGradient => LinearGradient(
        colors: [
          bgPrimary,
          bgSurface,
          bgPrimary,
        ],
        stops: const [0.0, 0.52, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Pre-configured Cyberpunk theme preset specification.
class AppThemePreset {
  final String id;
  final String name;
  final String subtitle;
  final AppColors colors;

  const AppThemePreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.colors,
  });

  Color get primaryColor => colors.neonPrimary;
  Color get secondaryColor => colors.neonSecondary;
  Color get backgroundColor => colors.bgPrimary;
  Color get surfaceColor => colors.bgSurface;
  Color get surfaceElevated => colors.cardGlass;
  Color get cardColor => colors.cardGlass;
  Color get textColor => colors.textPrimary;
  Color get textSecondaryColor => colors.textSecondary;

  LinearGradient get primarySecondaryGradient =>
      colors.primarySecondaryGradient;
  LinearGradient get secondaryPrimaryGradient =>
      colors.secondaryPrimaryGradient;
  LinearGradient get glassBorderGradient => colors.glassBorderGradient;
  LinearGradient get glassBorderGradientSoft => colors.glassBorderGradientSoft;
  LinearGradient get backgroundGradient => colors.backgroundGradient;

  static const List<AppThemePreset> presets = [
    // Пресет 1: "Cyber Core" (Cyan #00F0FF, Violet #9D4EDD, фон #07080C)
    AppThemePreset(
      id: 'cyber_core',
      name: 'Cyber Core',
      subtitle: 'Неоновый циан и фиолетовый на глубоком обсидиане',
      colors: AppColors(
        bgPrimary: Color(0xFF07080C),
        bgSurface: Color(0xFF0D111A),
        cardGlass: Color(0xFF0F121C),
        neonPrimary: Color(0xFF00F0FF),
        neonSecondary: Color(0xFF9D4EDD),
      ),
    ),
    // Пресет 2: "Matrix Protocol" (Green #00FF66, Dark Green #0A2012, фон #050B07)
    AppThemePreset(
      id: 'matrix_protocol',
      name: 'Matrix Protocol',
      subtitle: 'Кибертерминал, зеленый фосфор и цифровой матрикс',
      colors: AppColors(
        bgPrimary: Color(0xFF050B07),
        bgSurface: Color(0xFF08140B),
        cardGlass: Color(0xFF0C1D10),
        neonPrimary: Color(0xFF00FF66),
        neonSecondary: Color(0xFF0A2012),
      ),
    ),
    // Пресет 3: "Sunset Synth" (Pink #FF007F, Amber #FF8800, фон #0C0614)
    AppThemePreset(
      id: 'sunset_synth',
      name: 'Sunset Synth',
      subtitle: 'Ретровейв закат в розово-янтарных тонах',
      colors: AppColors(
        bgPrimary: Color(0xFF0C0614),
        bgSurface: Color(0xFF160B24),
        cardGlass: Color(0xFF1E1030),
        neonPrimary: Color(0xFFFF007F),
        neonSecondary: Color(0xFFFF8800),
      ),
    ),
    // Пресет 4: "Tokyo Crimson" (Red #FF003C, Chrome #E0E0E0, фон #0F0A0C)
    AppThemePreset(
      id: 'tokyo_crimson',
      name: 'Tokyo Crimson',
      subtitle: 'Алый неон ночного Токио и холодный хром',
      colors: AppColors(
        bgPrimary: Color(0xFF0F0A0C),
        bgSurface: Color(0xFF1A0F13),
        cardGlass: Color(0xFF221419),
        neonPrimary: Color(0xFFFF003C),
        neonSecondary: Color(0xFFE0E0E0),
      ),
    ),
    // Пресет 5: "Cold Ice" (Ice Blue #50E3C2, Deep Slate #1E293B, фон #060A12)
    AppThemePreset(
      id: 'cold_ice',
      name: 'Cold Ice',
      subtitle: 'Ледяной арктический циан и глухой сланец',
      colors: AppColors(
        bgPrimary: Color(0xFF060A12),
        bgSurface: Color(0xFF0A1220),
        cardGlass: Color(0xFF0E182A),
        neonPrimary: Color(0xFF50E3C2),
        neonSecondary: Color(0xFF1E293B),
      ),
    ),
  ];

  ThemeData get themeData {
    final baseTextTheme = Typography.material2021().white;

    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: colors.bgPrimary,
      canvasColor: colors.bgSurface,
      cardColor: colors.cardGlass,
      colorScheme: ColorScheme.dark(
        primary: colors.neonPrimary,
        onPrimary: Colors.black,
        secondary: colors.neonSecondary,
        onSecondary: Colors.white,
        tertiary: colors.neonPrimary.withValues(alpha: 0.8),
        surface: colors.bgSurface,
        onSurface: colors.textPrimary,
        error: colors.neonPink,
        onError: Colors.white,
      ),
      splashColor: colors.neonPrimary.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      textTheme: baseTextTheme.copyWith(
        displayLarge: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        headlineMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 0.2,
        ),
        titleMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          letterSpacing: 0.1,
        ),
        bodyLarge: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
        ),
        bodySmall: TextStyle(
          color: colors.textMuted,
          fontSize: 11,
        ),
        labelLarge: TextStyle(
          color: colors.neonPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
        labelSmall: TextStyle(
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 10,
          letterSpacing: 1.1,
        ),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.neonPrimary,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        thumbColor: Colors.white,
        overlayColor: colors.neonPrimary.withValues(alpha: 0.14),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.045),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.32),
          fontSize: 14,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.neonPrimary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.neonPink, width: 1),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.neonPrimary,
        selectionColor: colors.neonPrimary.withValues(alpha: 0.22),
        selectionHandleColor: colors.neonPrimary,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: colors.neonPrimary, size: 24),
        unselectedIconTheme: IconThemeData(
          color: Colors.white.withValues(alpha: 0.4),
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          color: colors.neonPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
        ),
        indicatorColor: colors.neonPrimary.withValues(alpha: 0.1),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.bgPrimary.withValues(alpha: 0.9),
        selectedItemColor: colors.neonPrimary,
        unselectedItemColor: Colors.white.withValues(alpha: 0.35),
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0x8CFFFFFF),
        indicatorColor: colors.neonPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        dividerColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.07),
        thickness: 0.5,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardGlass,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.cardGlass.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 11),
        waitDuration: const Duration(milliseconds: 450),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.16),
        ),
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(4),
      ),
    );
  }
}

/// Global theme controller managing active preset selection and SQLite persistence.
///
/// Implemented as a singleton with [ChangeNotifier] so any UI tree
/// can listen via [ListenableBuilder] and update automatically.
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();

  static const String metaKey = 'app_theme';

  /// ValueNotifier holding the active preset for direct subscription or testing.
  static final ValueNotifier<AppThemePreset> currentPreset =
      ValueNotifier<AppThemePreset>(AppThemePreset.presets[0]);

  AppThemePreset _currentPreset = AppThemePreset.presets[0];

  ThemeController._internal() {
    currentPreset.addListener(() {
      if (_currentPreset != currentPreset.value) {
        _currentPreset = currentPreset.value;
        notifyListeners();
      }
    });
  }

  /// Static shortcut to the active dynamic color palette.
  static AppColors get colors => currentPreset.value.colors;

  /// The active dynamic color palette of the controller.
  AppColors get currentColors => currentPreset.value.colors;

  /// The active preset of the controller.
  AppThemePreset get activePreset => currentPreset.value;

  /// The active ThemeData.
  ThemeData get currentThemeData => currentPreset.value.themeData;

  /// Backwards-compatible static getter for current preset.
  static AppThemePreset get current => currentPreset.value;

  /// Static initialization loading saved theme preset from SQLite.
  static Future<void> init() => instance.initTheme();

  /// Loads saved theme preset from SQLite or defaults to Cyber Core.
  Future<void> initTheme() async {
    try {
      final savedId = await DatabaseService.instance.getSyncMeta(metaKey);
      if (savedId != null && savedId.isNotEmpty) {
        final match = AppThemePreset.presets.firstWhere(
          (p) => p.id == savedId,
          orElse: () => AppThemePreset.presets[0],
        );
        _currentPreset = match;
        currentPreset.value = match;
        notifyListeners();
      }
    } catch (_) {
      // Default to Cyber Core on storage read error
    }
  }

  /// Sets and persists the new active theme preset.
  Future<void> setTheme(AppThemePreset preset) async {
    _currentPreset = preset;
    currentPreset.value = preset;
    notifyListeners();
    try {
      await DatabaseService.instance.setSyncMeta(metaKey, preset.id);
    } catch (_) {
      // Best-effort persistence
    }
  }

  /// Static alias for setTheme.
  static Future<void> setPreset(AppThemePreset preset) =>
      instance.setTheme(preset);
}

/// NCmus premium Dark Glassmorphism palette.
///
/// Dynamically resolves all color properties to [ThemeController.colors].
class CyberpunkTheme {
  CyberpunkTheme._();

  // ---------------------------------------------------------------------------
  // Core surfaces (dynamic getters forwarding to active ThemeController preset)
  // ---------------------------------------------------------------------------
  static Color get backgroundColor => ThemeController.colors.bgPrimary;
  static Color get backgroundDeep => ThemeController.colors.bgPrimary;
  static Color get surfaceColor => ThemeController.colors.bgSurface;
  static Color get surfaceElevated => ThemeController.colors.cardGlass;
  static Color get cardColor => ThemeController.colors.cardGlass;

  // ---------------------------------------------------------------------------
  // Accents (dynamic getters forwarding to active ThemeController preset)
  // ---------------------------------------------------------------------------
  static Color get neonCyan => ThemeController.colors.neonPrimary;
  static Color get electricViolet => ThemeController.colors.neonSecondary;
  static Color get neonPurple => ThemeController.colors.neonSecondary;
  static Color get neonPink => ThemeController.colors.neonPink;
  static Color get neonGreen => ThemeController.colors.neonGreen;
  static Color get neonAmber => ThemeController.colors.neonAmber;

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------
  static Color get textPrimary => ThemeController.colors.textPrimary;
  static Color get textSecondary => ThemeController.colors.textSecondary;
  static Color get textMuted => ThemeController.colors.textMuted;

  // ---------------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------------
  static LinearGradient get cyanVioletGradient =>
      ThemeController.colors.primarySecondaryGradient;

  static LinearGradient get violetCyanGradient =>
      ThemeController.colors.secondaryPrimaryGradient;

  /// Kept for compatibility with older widgets.
  static LinearGradient get cyanPinkGradient => cyanVioletGradient;
  static LinearGradient get purpleCyanGradient => violetCyanGradient;

  static LinearGradient get glassBorderGradient =>
      ThemeController.colors.glassBorderGradient;

  static LinearGradient get glassBorderGradientSoft =>
      ThemeController.colors.glassBorderGradientSoft;

  static LinearGradient get backgroundGradient =>
      ThemeController.colors.backgroundGradient;

  static List<BoxShadow> glow(
    Color color, {
    double blur = 26,
    double opacity = 0.22,
    double spread = 1,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Active ThemeData
  // ---------------------------------------------------------------------------
  static ThemeData get darkTheme => ThemeController.instance.currentThemeData;
}

/// Premium frosted-glass surface with a real backdrop blur, a hairline
/// gradient border and an optional ambient glow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final double backgroundOpacity;
  final Gradient? backgroundGradient;
  final Gradient? borderGradient;
  final Border? border;
  final Color? glowColor;
  final List<BoxShadow>? shadows;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 18,
    this.blur = 16,
    this.backgroundOpacity = 0.05,
    this.backgroundGradient,
    this.borderGradient,
    this.border,
    this.glowColor,
    this.shadows,
    this.width,
    this.height,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThemeController.colors;
    final radius = BorderRadius.circular(borderRadius);
    final effectiveBackground = backgroundGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: backgroundOpacity),
            Colors.white.withValues(alpha: backgroundOpacity * 0.45),
          ],
        );

    final Widget frosted = ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: effectiveBackground,
            borderRadius: radius,
          ),
          child: onTap != null
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: onTap,
                    splashColor: colors.neonPrimary.withValues(alpha: 0.12),
                    highlightColor: colors.neonPrimary.withValues(alpha: 0.05),
                    hoverColor: colors.neonPrimary.withValues(alpha: 0.03),
                    child: padding != null
                        ? Padding(padding: padding!, child: child)
                        : child,
                  ),
                )
              : (padding != null
                  ? Padding(padding: padding!, child: child)
                  : child),
        ),
      ),
    );

    final effectiveBorderGradient =
        borderGradient ?? colors.glassBorderGradientSoft;
    final hasGradientBorder = border == null;
    final borderShadows = <BoxShadow>[
      if (glowColor != null)
        BoxShadow(
          color: glowColor!.withValues(alpha: 0.18),
          blurRadius: 30,
          spreadRadius: 1,
        ),
      ...?shadows,
    ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: hasGradientBorder ? const EdgeInsets.all(0.5) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: hasGradientBorder ? effectiveBorderGradient : null,
        border: hasGradientBorder
            ? null
            : (border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                )),
        boxShadow: borderShadows.isEmpty ? null : borderShadows,
      ),
      child: frosted,
    );
  }
}

/// Backwards-compatible glass container used by older screens.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadiusGeometry borderRadius;
  final Gradient? borderGradient;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? width;
  final double? height;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 16.0,
    this.opacity = 0.05,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.borderGradient,
    this.border,
    this.padding,
    this.margin,
    this.color,
    this.width,
    this.height,
    this.shadows,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThemeController.colors;
    final effectiveBorder = border ??
        Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        );

    final background = (color ?? Colors.white).withValues(alpha: opacity);

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
              border: borderGradient == null ? effectiveBorder : null,
            ),
            child: child,
          ),
        ),
      ),
    );

    final effectiveGradient = borderGradient ?? colors.glassBorderGradientSoft;

    content = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: effectiveGradient,
        boxShadow: shadows,
      ),
      padding: const EdgeInsets.all(0.5),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}
