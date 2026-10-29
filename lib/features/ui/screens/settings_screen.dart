import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/discord_rpc_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../wave/services/nc_wave_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings screen for NCmus featuring theme preset customization,
/// blacklist management, and audio core diagnostics.
class SettingsScreen extends StatefulWidget {
  final NCPlayerHandler handler;

  const SettingsScreen({
    super.key,
    required this.handler,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _discordRpcEnabled = true;

  @override
  void initState() {
    super.initState();
    DatabaseService.instance.getBlacklistCount();
    _loadDiscordRpcSetting();
  }

  Future<void> _loadDiscordRpcSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _discordRpcEnabled = prefs.getBool(DiscordRpcService.prefKey) ?? true;
      });
    }
  }

  Future<void> _toggleDiscordRpc(bool value) async {
    setState(() {
      _discordRpcEnabled = value;
    });
    await DiscordRpcService.instance.setEnabled(value);
  }

  Future<void> _clearBlacklist() async {
    try {
      if (NCWaveService.instance != null) {
        await NCWaveService.instance!.clearBlacklist();
      } else {
        await DatabaseService.instance.clearBlacklist();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: ThemeController.currentPreset,
      builder: (context, activePreset, _) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(activePreset),
                  const SizedBox(height: 28),
                  _buildSectionTitle(
                    title: 'НЕОНОВЫЕ ПАЛИТРЫ И ТЕМЫ',
                    subtitle:
                        'Выберите цветовую гамму интерфейса. Изменения применяются мгновенно.',
                    icon: Icons.palette_outlined,
                    accentColor: activePreset.primaryColor,
                  ),
                  const SizedBox(height: 14),
                  _buildThemeCardsGrid(activePreset),
                  const SizedBox(height: 32),
                  _buildSectionTitle(
                    title: 'NC-ВОЛНА И ЧЁРНЫЙ СПИСОК',
                    subtitle:
                        'Управление отклонёнными треками и алгоритмом умной дедупликации.',
                    icon: Icons.thumb_down_outlined,
                    accentColor: activePreset.secondaryColor,
                  ),
                  const SizedBox(height: 14),
                  _buildBlacklistCard(activePreset),
                  const SizedBox(height: 32),
                  _buildSectionTitle(
                    title: 'ИНТЕГРАЦИИ & DISCORD RPC',
                    subtitle:
                        'Отображение текущего трека и статуса воспроизведения в профиле Discord.',
                    icon: Icons.sports_esports_rounded,
                    accentColor: const Color(0xFF5865F2),
                  ),
                  const SizedBox(height: 14),
                  _buildDiscordRpcCard(activePreset),
                  const SizedBox(height: 32),
                  _buildSectionTitle(
                    title: 'О СИСТЕМЕ & LOCAL-FIRST',
                    subtitle:
                        'Параметры локального хранилища SQLite и автономного аудиоядра.',
                    icon: Icons.memory_rounded,
                    accentColor: CyberpunkTheme.neonGreen,
                  ),
                  const SizedBox(height: 14),
                  _buildAboutCard(activePreset),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(AppThemePreset activePreset) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                activePreset.primaryColor.withValues(alpha: 0.25),
                activePreset.secondaryColor.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(
              color: activePreset.primaryColor.withValues(alpha: 0.4),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: activePreset.primaryColor.withValues(alpha: 0.2),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.tune_rounded,
            color: activePreset.primaryColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'НАСТРОЙКИ СИСТЕМЫ',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Конфигурация тем оформления, аудиоядра и умной волны',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: accentColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeCardsGrid(AppThemePreset activePreset) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 580;
        final crossAxisCount = isWide ? 2 : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: isWide ? 2.2 : 2.5,
          ),
          itemCount: AppThemePreset.presets.length,
          itemBuilder: (context, index) {
            final preset = AppThemePreset.presets[index];
            final isSelected = activePreset.id == preset.id;

            return _ThemePresetCard(
              preset: preset,
              isSelected: isSelected,
              onTap: () async {
                await ThemeController.setPreset(preset);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBlacklistCard(AppThemePreset activePreset) {
    return GlassCard(
      borderRadius: 18,
      blur: 16,
      backgroundOpacity: 0.045,
      padding: const EdgeInsets.all(18),
      child: ValueListenableBuilder<int>(
        valueListenable: DatabaseService.blacklistCount,
        builder: (context, count, _) {
          return Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.block_rounded,
                  color: CyberpunkTheme.neonPink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ЧЁРНЫЙ СПИСОК ВОЛНЫ',
                          style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: DatabaseService.blacklistCount,
                          builder: (context, count, _) => Text(
                            '$count треков',
                            style: TextStyle(
                              color: CyberpunkTheme.neonPink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Отклонённые треки и их вариации мгновенно исключаются из потока воспроизведения.',
                      style: TextStyle(
                        color: CyberpunkTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: count > 0 ? _clearBlacklist : null,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  backgroundColor: count > 0
                      ? CyberpunkTheme.neonPink.withValues(alpha: 0.12)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: count > 0
                          ? CyberpunkTheme.neonPink.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Text(
                  'СБРОСИТЬ',
                  style: TextStyle(
                    color: count > 0
                        ? CyberpunkTheme.neonPink
                        : Colors.white.withValues(alpha: 0.3),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiscordRpcCard(AppThemePreset activePreset) {
    return GlassCard(
      borderRadius: 18,
      blur: 16,
      backgroundOpacity: 0.05,
      borderGradient: CyberpunkTheme.glassBorderGradientSoft,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF5865F2).withValues(alpha: 0.16),
              border: Border.all(
                color: const Color(0xFF5865F2).withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              color: Color(0xFF5865F2),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Трансляция статуса в Discord',
                  style: TextStyle(
                    color: CyberpunkTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Передаёт название трека, исполнителя и таймлайн в Rich Presence',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _discordRpcEnabled,
            onChanged: _toggleDiscordRpc,
            activeThumbColor: activePreset.primaryColor,
            activeTrackColor: activePreset.primaryColor.withValues(alpha: 0.35),
            inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(AppThemePreset activePreset) {
    return GlassCard(
      borderRadius: 18,
      blur: 16,
      backgroundOpacity: 0.045,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 38,
                    height: 38,
                    color: activePreset.primaryColor.withValues(alpha: 0.2),
                    child: Icon(Icons.music_note, color: activePreset.primaryColor),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NCMUS · CYBERPUNK MUSIC SUITE',
                      style: TextStyle(
                        color: CyberpunkTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Версия 1.0.0 (Local-First Engine)',
                      style: TextStyle(
                        color: CyberpunkTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 12),
          _buildInfoRow('Хранилище данных', 'Локальная база SQLite (ncmus.db)'),
          const SizedBox(height: 6),
          _buildInfoRow('Каталог загрузок', 'Локальная папка Music/NCmus'),
          const SizedBox(height: 6),
          _buildInfoRow('Аудиоядро', 'just_audio + Windows Platform Channel'),
          const SizedBox(height: 6),
          _buildInfoRow('Телеметрия', 'Отключена (0 байт наружу)'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: CyberpunkTheme.textMuted,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: CyberpunkTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  final AppThemePreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePresetCard({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      blur: 16,
      backgroundOpacity: isSelected ? 0.12 : 0.04,
      borderGradient: isSelected
          ? LinearGradient(
              colors: [
                preset.primaryColor,
                preset.secondaryColor.withValues(alpha: 0.8),
              ],
            )
          : null,
      glowColor: isSelected ? preset.primaryColor : null,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : CyberpunkTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: preset.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: preset.primaryColor.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: preset.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'АКТИВНО',
                        style: TextStyle(
                          color: preset.primaryColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Text(
            preset.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected
                  ? preset.primaryColor.withValues(alpha: 0.85)
                  : CyberpunkTheme.textMuted,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Swatch 1: Primary
              _buildSwatch(
                color: preset.primaryColor,
                tooltip: 'Primary',
              ),
              const SizedBox(width: 6),
              // Swatch 2: Secondary
              _buildSwatch(
                color: preset.secondaryColor,
                tooltip: 'Secondary',
              ),
              const SizedBox(width: 6),
              // Swatch 3: Background
              _buildSwatch(
                color: preset.backgroundColor,
                tooltip: 'Background',
                hasBorder: true,
              ),
              const SizedBox(width: 10),
              // Gradient Preview Bar
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: preset.primarySecondaryGradient,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwatch({
    required Color color,
    required String tooltip,
    bool hasBorder = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: hasBorder
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.15),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
