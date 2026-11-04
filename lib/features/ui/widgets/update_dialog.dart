import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/android_platform_service.dart';
import '../../../core/services/update_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';

/// Shared UI flow for checking, downloading and installing GitHub releases.
class UpdateDialog {
  UpdateDialog._();

  static bool _checking = false;

  /// Checks GitHub and shows the available-update dialog.
  ///
  /// [silent] suppresses the "already up to date" and error messages, which is
  /// used by the automatic startup check.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silent = false,
    bool showLatestMessage = true,
  }) async {
    if (_checking) return;
    _checking = true;

    try {
      final currentVersion = await UpdateService.currentVersion();
      final update = await UpdateService.checkForUpdate();

      if (!context.mounted) return;

      if (update == null) {
        if (!silent && showLatestMessage) {
          _showSnack(
            context,
            'Установлена последняя версия NCmus ($currentVersion).',
          );
        }
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return _UpdateAvailableDialog(
            update: update,
            currentVersion: currentVersion,
            onInstall: () {
              Navigator.of(dialogContext).pop();
              unawaited(_downloadAndInstall(context, update));
            },
          );
        },
      );
    } on UpdateException catch (error) {
      if (context.mounted && !silent) {
        _showSnack(context, error.message, isError: true);
      }
    } catch (error) {
      if (context.mounted && !silent) {
        _showSnack(
          context,
          'Не удалось проверить обновления: $error',
          isError: true,
        );
      }
    } finally {
      _checking = false;
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    AppUpdate update,
  ) async {
    if (!AndroidPlatformService.isAndroid) {
      _showSnack(
        context,
        'Автоматическая установка доступна только на Android. '
        'Скачайте APK со страницы релиза GitHub.',
      );
      return;
    }

    final progress = ValueNotifier<double>(0);
    var progressOpen = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: CyberpunkTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: CyberpunkTheme.neonCyan.withValues(alpha: 0.35),
                ),
              ),
              title: Text(
                'ЗАГРУЗКА NCmus ${update.version}',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              content: SizedBox(
                width: 360,
                child: ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, _) {
                    final percent =
                        (value * 100).clamp(0, 100).toStringAsFixed(0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: value <= 0 ? null : value,
                            minHeight: 8,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            color: CyberpunkTheme.neonCyan,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value <= 0
                              ? 'Подключение к GitHub…'
                              : 'Скачано $percent%',
                          style: TextStyle(
                            color: CyberpunkTheme.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );

    void closeProgress() {
      if (!progressOpen) return;
      progressOpen = false;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      // Let the dialog route finish its exit animation before the notifier
      // that it listens to is released.
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        progress.dispose,
      );
    }

    try {
      final file = await UpdateService.downloadUpdate(
        update,
        onProgress: (received, total) {
          if (total > 0) {
            progress.value = (received / total).clamp(0.0, 1.0);
          }
        },
      );

      closeProgress();

      final status = await UpdateService.installUpdate(file);
      if (!context.mounted) return;

      switch (status) {
        case ApkInstallStatus.started:
          _showSnack(
            context,
            'Установщик Android открыт. Подтвердите установку обновления.',
          );
        case ApkInstallStatus.permissionRequired:
          await _showInstallPermissionDialog(context);
        case ApkInstallStatus.signatureMismatch:
          await _showSignatureMismatchDialog(context, update);
        case ApkInstallStatus.unsupported:
          _showSnack(
            context,
            'Установка APK поддерживается только на Android.',
          );
      }
    } on UpdateException catch (error) {
      closeProgress();
      if (context.mounted) {
        _showSnack(context, error.message, isError: true);
      }
    } catch (error) {
      closeProgress();
      if (context.mounted) {
        _showSnack(
          context,
          'Не удалось установить обновление: $error',
          isError: true,
        );
      }
    }
  }

  static Future<void> _showInstallPermissionDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CyberpunkTheme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: CyberpunkTheme.neonPink.withValues(alpha: 0.35),
            ),
          ),
          title: Text(
            'НУЖНО РАЗРЕШЕНИЕ',
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          content: Text(
            'Android запрещает установку APK из этого источника. '
            'Разрешите «Установка неизвестных приложений» для NCmus, '
            'затем нажмите «Обновить» ещё раз.',
            style: TextStyle(
              color: CyberpunkTheme.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ПОЗЖЕ'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(AndroidPlatformService.openInstallSettings());
              },
              style: FilledButton.styleFrom(
                backgroundColor: CyberpunkTheme.neonCyan,
                foregroundColor: Colors.black,
              ),
              child: const Text('ОТКРЫТЬ НАСТРОЙКИ'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showSignatureMismatchDialog(
    BuildContext context,
    AppUpdate update,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CyberpunkTheme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: CyberpunkTheme.neonPink.withValues(alpha: 0.45),
            ),
          ),
          title: Text(
            'ПОДПИСЬ APK НЕ СОВПАДАЕТ',
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          content: Text(
            'Новый APK подписан другим ключом, чем установленная версия NCmus, '
            'поэтому Android не может установить его поверх. '
            'Удалите старую версию приложения и установите APK v${update.version} '
            'с GitHub Releases вручную. Все последующие обновления будут '
            'устанавливаться автоматически.',
            style: TextStyle(
              color: CyberpunkTheme.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ПОЗЖЕ'),
            ),
            if (update.releaseUrl.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(AndroidPlatformService.openUrl(update.releaseUrl));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: CyberpunkTheme.neonPink,
                  foregroundColor: Colors.white,
                ),
                child: const Text('ОТКРЫТЬ GITHUB'),
              ),
          ],
        );
      },
    );
  }

  static void _showSnack(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor:
              isError ? const Color(0xFF371523) : const Color(0xFF141322),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color:
                  (isError ? CyberpunkTheme.neonPink : CyberpunkTheme.neonCyan)
                      .withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
        ),
      );
  }
}

class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({
    required this.update,
    required this.currentVersion,
    required this.onInstall,
  });

  final AppUpdate update;
  final String currentVersion;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final releaseNotes =
        update.body.isEmpty ? 'Описание релиза не указано.' : update.body;

    return AlertDialog(
      backgroundColor: CyberpunkTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: CyberpunkTheme.neonCyan.withValues(alpha: 0.35),
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: CyberpunkTheme.neonCyan.withValues(alpha: 0.14),
              border: Border.all(
                color: CyberpunkTheme.neonCyan.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              color: CyberpunkTheme.neonCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ДОСТУПНО ОБНОВЛЕНИЕ',
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildVersionBadge('УСТАНОВЛЕНО', 'v$currentVersion'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Colors.white38,
                      ),
                    ),
                    _buildVersionBadge(
                      'НОВАЯ ВЕРСИЯ',
                      'v${update.version}',
                      accent: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'ЧТО НОВОГО',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  releaseNotes,
                  style: TextStyle(
                    color: CyberpunkTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (update.apkSize > 0) ...[
                  const SizedBox(height: 14),
                  Text(
                    'APK · ${_formatSize(update.apkSize)}',
                    style: TextStyle(
                      color: CyberpunkTheme.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ПОЗЖЕ'),
        ),
        FilledButton.icon(
          onPressed: onInstall,
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('ОБНОВИТЬ'),
          style: FilledButton.styleFrom(
            backgroundColor: CyberpunkTheme.neonCyan,
            foregroundColor: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildVersionBadge(
    String label,
    String version, {
    bool accent = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: (accent ? CyberpunkTheme.neonCyan : Colors.white)
            .withValues(alpha: accent ? 0.12 : 0.04),
        border: Border.all(
          color: (accent ? CyberpunkTheme.neonCyan : Colors.white)
              .withValues(alpha: accent ? 0.4 : 0.1),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  accent ? CyberpunkTheme.neonCyan : CyberpunkTheme.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            version,
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    }
    return '$bytes Б';
  }
}
