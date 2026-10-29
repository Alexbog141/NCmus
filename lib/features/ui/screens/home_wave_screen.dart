import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../wave/services/nc_wave_service.dart';
import '../../wave/services/wave_service.dart';
import '../widgets/cyber_fluid_wave.dart';
import '../widgets/cyber_visualizer.dart';

class _GenreCardData {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> seeds;
  final Color primaryColor;
  final Color secondaryColor;

  const _GenreCardData({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.seeds,
    required this.primaryColor,
    required this.secondaryColor,
  });
}

/// Home screen dedicated to NC-Wave (умный бесконечный поток музыки) and Genre Hub.
class HomeWaveScreen extends StatefulWidget {
  final NCPlayerHandler handler;
  final NCWaveService? waveService;

  const HomeWaveScreen({
    super.key,
    required this.handler,
    this.waveService,
  });

  @override
  State<HomeWaveScreen> createState() => _HomeWaveScreenState();
}

class _HomeWaveScreenState extends State<HomeWaveScreen> {
  String? _selectedGenreId;
  bool _isStartingWave = false;

  static final List<_GenreCardData> _genres = [
    _GenreCardData(
      id: 'cyberpunk',
      emoji: '⚡',
      title: 'Киберпанк',
      subtitle: 'Cyberpunk 2077 · Synthwave · Darksynth',
      seeds: const ['Cyberpunk 2077', 'Synthwave', 'Darksynth'],
      primaryColor: ThemeController.colors.neonPrimary,
      secondaryColor: ThemeController.colors.neonSecondary,
    ),
    _GenreCardData(
      id: 'phonk',
      emoji: '🏎️',
      title: 'Фонк',
      subtitle: 'Phonk · Drift Phonk · Aggressive Phonk',
      seeds: const ['Phonk', 'Drift Phonk'],
      primaryColor: const Color(0xFFFF0055),
      secondaryColor: ThemeController.colors.neonSecondary,
    ),
    const _GenreCardData(
      id: 'rock',
      emoji: '🎸',
      title: 'Рок & Альтернатива',
      subtitle: 'Alternative Rock · Nu Metal · Rock',
      seeds: ['Alternative Rock', 'Nu Metal', 'Rock'],
      primaryColor: Color(0xFF9D4EDD),
      secondaryColor: Color(0xFFFF003C),
    ),
    const _GenreCardData(
      id: 'lo_fi',
      emoji: '☕',
      title: 'Lo-Fi & Чилл',
      subtitle: 'Lo-Fi Hip Hop · Chillstep · Ambient',
      seeds: ['Lo-Fi Hip Hop', 'Chillstep'],
      primaryColor: Color(0xFFF4B860),
      secondaryColor: Color(0xFFFF8800),
    ),
    const _GenreCardData(
      id: 'post_punk',
      emoji: '🖤',
      title: 'Пост-панк',
      subtitle: 'Post-Punk · Doomer · Sovietwave',
      seeds: ['Post-Punk', 'Doomer', 'Sovietwave'],
      primaryColor: Color(0xFF50E3C2),
      secondaryColor: Color(0xFF4A5568),
    ),
    _GenreCardData(
      id: 'my_mix',
      emoji: '🎲',
      title: 'Мой Микс',
      subtitle: 'Персональная волна на основе медиатеки',
      seeds: const ['my_mix'],
      primaryColor: ThemeController.colors.neonPrimary,
      secondaryColor: const Color(0xFF4ADE80),
    ),
    const _GenreCardData(
      id: 'synthwave',
      emoji: '🌌',
      title: 'Синтвейв & 80s',
      subtitle: 'Retrowave · Neon Electro · Outrun',
      seeds: ['Synthwave', 'Retrowave', 'Outrun'],
      primaryColor: Color(0xFFFF007F),
      secondaryColor: Color(0xFF00F0FF),
    ),
    const _GenreCardData(
      id: 'electro',
      emoji: '🎧',
      title: 'Электроника & EDM',
      subtitle: 'Dark Techno · Club · Cyber Beats',
      seeds: ['Dark Techno', 'Electronic', 'Cyber Techno'],
      primaryColor: Color(0xFF00E5FF),
      secondaryColor: Color(0xFF7C4DFF),
    ),
  ];

  Future<void> _startGenreWave(_GenreCardData genre) async {
    setState(() {
      _selectedGenreId = genre.id;
      _isStartingWave = true;
    });

    try {
      if (widget.waveService != null) {
        await widget.waveService!.startWaveForGenre(genre.title, genre.seeds);
      } else {
        await WaveService.instance
            .startWave(genreId: genre.title, forceRestart: true);
      }
    } catch (_) {
      // Best-effort startup without SnackBar
    } finally {
      if (mounted) {
        setState(() {
          _isStartingWave = false;
        });
      }
    }
  }

  Future<void> _toggleMainWave() async {
    final wave = WaveService.instance;

    if (wave.isWaveActive || (widget.waveService?.isWaveActive ?? false)) {
      wave.stopWave();
      widget.waveService?.stopWave();
      setState(() {
        _selectedGenreId = null;
      });
    } else {
      setState(() {
        _selectedGenreId = 'my_mix';
        _isStartingWave = true;
      });
      try {
        if (widget.waveService != null) {
          await widget.waveService!.startWave(forceRestart: true);
        } else {
          await wave.startWave(forceRestart: true);
        }
      } catch (_) {
        // Continue silently
      } finally {
        if (mounted) {
          setState(() {
            _isStartingWave = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wave = WaveService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [wave, widget.waveService].whereType<Listenable>().toList()),
      builder: (context, _) {
        final isWaveActive =
            wave.isWaveActive || (widget.waveService?.isWaveActive ?? false);
        final activeGenre = wave.activeGenre ?? widget.waveService?.activeGenre;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroBanner(
                    isWaveActive: isWaveActive,
                    activeGenre: activeGenre,
                  ),
                  const SizedBox(height: 28),
                  _buildGenreHeader(),
                  const SizedBox(height: 16),
                  _buildGenreGrid(
                    isWaveActive: isWaveActive,
                    activeGenre: activeGenre,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroBanner({
    required bool isWaveActive,
    required String? activeGenre,
  }) {
    return GlassCard(
      borderRadius: 24,
      blur: 24,
      backgroundOpacity: isWaveActive ? 0.08 : 0.05,
      borderGradient: isWaveActive
          ? CyberpunkTheme.glassBorderGradient
          : CyberpunkTheme.glassBorderGradientSoft,
      glowColor: isWaveActive ? CyberpunkTheme.neonCyan : null,
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 580;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isWaveActive
                          ? CyberpunkTheme.neonCyan.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: isWaveActive
                            ? CyberpunkTheme.neonCyan.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isWaveActive
                                ? CyberpunkTheme.neonGreen
                                : CyberpunkTheme.textMuted,
                            boxShadow: isWaveActive
                                ? [
                                    BoxShadow(
                                      color: CyberpunkTheme.neonGreen
                                          .withValues(alpha: 0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isWaveActive
                              ? 'ВОЛНА АКТИВНА ${activeGenre != null ? '· $activeGenre' : ''}'
                              : 'ИНТЕЛЛЕКТУАЛЬНЫЙ ПОТОК',
                          style: TextStyle(
                            color: isWaveActive
                                ? CyberpunkTheme.neonCyan
                                : CyberpunkTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (isWaveActive) ...[
                          const SizedBox(width: 8),
                          CyberVisualizer(
                            isPlaying: true,
                            barCount: 4,
                            maxHeight: 12,
                            color: CyberpunkTheme.neonGreen,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'NC-ВОЛНА',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Text(
                  'Бесконечный адаптивный поток треков. Система анализирует ваши предпочтения, исключает повторы и забаненные треки, обеспечивая непрерывное погружение.',
                  style: TextStyle(
                    color: CyberpunkTheme.textSecondary.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isStartingWave ? null : _toggleMainWave,
                icon: _isStartingWave
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Icon(
                        isWaveActive
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
                label: Text(
                  isWaveActive ? 'ОСТАНОВИТЬ ВОЛНУ' : 'ЗАПУСТИТЬ МОЙ МИКС',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isWaveActive
                      ? CyberpunkTheme.neonCyan
                      : CyberpunkTheme.neonGreen,
                  elevation: 8,
                  shadowColor: (isWaveActive
                          ? CyberpunkTheme.neonCyan
                          : CyberpunkTheme.neonGreen)
                      .withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          );

          final orb = SizedBox(
            width: 150,
            height: 150,
            child: CyberFluidOrb(
              handler: widget.handler,
              size: 150,
            ),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: content),
                const SizedBox(width: 20),
                orb,
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 20),
                Center(child: orb),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildGenreHeader() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CyberpunkTheme.neonCyan.withValues(alpha: 0.1),
            border: Border.all(
              color: CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Icon(
            Icons.waves_rounded,
            color: CyberpunkTheme.neonCyan,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ЖАНРОВЫЙ ХАБ · НАСТРОЕНИЯ',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Нажмите на карточку, чтобы мгновенно включить поток выбранного жанра',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenreGrid({
    required bool isWaveActive,
    required String? activeGenre,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 640;
        final crossAxisCount = isWide ? 4 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: isWide ? 1.45 : 1.3,
          ),
          itemCount: _genres.length,
          itemBuilder: (context, index) {
            final item = _genres[index];
            final isSelected = isWaveActive &&
                (activeGenre == item.title || _selectedGenreId == item.id);

            return _GenreCard(
              data: item,
              isSelected: isSelected,
              isBusy: _isStartingWave && _selectedGenreId == item.id,
              onTap: () => _startGenreWave(item),
            );
          },
        );
      },
    );
  }
}

class _GenreCard extends StatefulWidget {
  final _GenreCardData data;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;

  const _GenreCard({
    required this.data,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
  });

  @override
  State<_GenreCard> createState() => _GenreCardState();
}

class _GenreCardState extends State<_GenreCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isSelected = widget.isSelected;
    final isBusy = widget.isBusy;
    final isHovered = _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: isHovered ? 1.025 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (isSelected || isHovered)
                BoxShadow(
                  color: (isSelected ? data.primaryColor : data.secondaryColor)
                      .withValues(alpha: isHovered ? 0.32 : 0.16),
                  blurRadius: isHovered ? 26 : 14,
                  spreadRadius: isHovered ? 2 : 0,
                ),
            ],
          ),
          child: GlassCard(
            borderRadius: 20,
            blur: 16,
            backgroundOpacity: isSelected ? 0.14 : (isHovered ? 0.085 : 0.045),
            borderGradient: isSelected
                ? LinearGradient(
                    colors: [
                      data.primaryColor,
                      data.secondaryColor,
                    ],
                  )
                : (isHovered
                    ? LinearGradient(
                        colors: [
                          data.primaryColor.withValues(alpha: 0.85),
                          data.secondaryColor.withValues(alpha: 0.85),
                        ],
                      )
                    : null),
            glowColor: isSelected
                ? data.primaryColor
                : (isHovered ? data.primaryColor.withValues(alpha: 0.6) : null),
            onTap: widget.onTap,
            padding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: Opacity(
                    opacity: isSelected ? 0.22 : (isHovered ? 0.16 : 0.08),
                    child: Text(
                      data.emoji,
                      style: const TextStyle(fontSize: 54),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                data.primaryColor.withValues(
                                  alpha: isHovered ? 0.38 : 0.28,
                                ),
                                data.secondaryColor.withValues(
                                  alpha: isHovered ? 0.22 : 0.15,
                                ),
                              ],
                            ),
                            border: Border.all(
                              color: data.primaryColor.withValues(
                                alpha: isSelected
                                    ? 0.85
                                    : (isHovered ? 0.6 : 0.35),
                              ),
                              width: isSelected || isHovered ? 1.2 : 0.6,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              data.emoji,
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                        if (isSelected || isBusy)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: data.primaryColor.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: data.primaryColor.withValues(alpha: 0.7),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isBusy)
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: data.primaryColor,
                                    ),
                                  )
                                else ...[
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 12,
                                    color: data.primaryColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'ВОЛНА',
                                    style: TextStyle(
                                      color: data.primaryColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected || isHovered
                                ? Colors.white
                                : CyberpunkTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          data.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected || isHovered
                                ? data.primaryColor.withValues(alpha: 0.95)
                                : CyberpunkTheme.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
