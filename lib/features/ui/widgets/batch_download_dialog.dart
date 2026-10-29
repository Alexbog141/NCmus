import 'package:flutter/material.dart';

import '../../../core/theme/cyberpunk_theme.dart';
import '../../library/services/batch_downloader_service.dart';
import '../../storage/models/track_entity.dart';

/// Cyberpunk modal dialog displaying realtime batch download progress,
/// worker status, current track title and backgrounding/cancellation controls.
class BatchDownloadDialog extends StatefulWidget {
  final List<TrackEntity> tracks;

  const BatchDownloadDialog({
    super.key,
    required this.tracks,
  });

  @override
  State<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<BatchDownloadDialog> {
  int _completed = 0;
  int _total = 0;
  String _currentTitle = 'Подготовка очереди загрузки...';
  bool _isDone = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _startBatch();
  }

  void _startBatch() {
    BatchDownloaderService.instance
        .downloadTracks(
      tracks: widget.tracks,
      onProgress: (completed, total, currentTitle) {
        if (!mounted) return;
        setState(() {
          _completed = completed;
          _total = total;
          if (currentTitle.isNotEmpty) {
            _currentTitle = currentTitle;
          }
          if (completed >= total && total > 0) {
            _isDone = true;
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _lastError = error;
        });
      },
    )
        .then((_) {
      if (mounted) {
        setState(() {
          _isDone = true;
        });
      }
    });
  }

  void _cancelDownload() {
    BatchDownloaderService.instance.cancel();
    Navigator.of(context).pop();
  }

  void _runInBackground() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final double progress =
        _total > 0 ? (_completed / _total).clamp(0.0, 1.0) : 0.0;
    final int percent = (progress * 100).toInt();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: Colors.transparent,
            child: GlassCard(
              borderRadius: 22,
              blur: 24,
              backgroundOpacity: 0.12,
              borderGradient: LinearGradient(
                colors: [
                  CyberpunkTheme.neonCyan.withValues(alpha: 0.8),
                  CyberpunkTheme.electricViolet.withValues(alpha: 0.5),
                  CyberpunkTheme.neonPink.withValues(alpha: 0.4),
                ],
              ),
              padding: const EdgeInsets.all(24),
              glowColor: CyberpunkTheme.neonCyan,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
                              CyberpunkTheme.electricViolet
                                  .withValues(alpha: 0.15),
                            ],
                          ),
                          border: Border.all(
                            color:
                                CyberpunkTheme.neonCyan.withValues(alpha: 0.6),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CyberpunkTheme.neonCyan
                                  .withValues(alpha: 0.25),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isDone
                              ? Icons.check_circle_rounded
                              : Icons.download_for_offline_rounded,
                          color: _isDone
                              ? CyberpunkTheme.neonGreen
                              : CyberpunkTheme.neonCyan,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'СИНХРОНИЗАЦИЯ ОФЛАЙН-МЕДИАТЕКИ',
                              style: TextStyle(
                                color: CyberpunkTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isDone
                                  ? 'Все треки успешно загружены на устройство'
                                  : 'Многопоточный пул: до 3 аудиопотоков одновременно',
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
                  const SizedBox(height: 22),

                  // 2. Progress Counter & Percent
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Загружено $_completed из $_total',
                        style: TextStyle(
                          color: CyberpunkTheme.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: _isDone
                              ? CyberpunkTheme.neonGreen
                              : CyberpunkTheme.neonCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 3. Neon Progress Bar
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 300),
                        widthFactor: progress,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                CyberpunkTheme.neonCyan,
                                CyberpunkTheme.electricViolet,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: CyberpunkTheme.neonCyan
                                    .withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 4. Current Track Title
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isDone
                              ? Icons.done_all_rounded
                              : Icons.music_note_rounded,
                          size: 16,
                          color: _isDone
                              ? CyberpunkTheme.neonGreen
                              : CyberpunkTheme.neonCyan,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isDone ? 'Синхронизация завершена' : _currentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CyberpunkTheme.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lastError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CyberpunkTheme.neonPink,
                        fontSize: 10.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 5. Actions
                  if (_isDone) ...[
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CyberpunkTheme.neonGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 6,
                        shadowColor:
                            CyberpunkTheme.neonGreen.withValues(alpha: 0.4),
                      ),
                      child: const Text(
                        'ЗАКРЫТЬ',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _runInBackground,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: CyberpunkTheme.neonCyan
                                    .withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'В ФОНОВЫЙ РЕЖИМ',
                              style: TextStyle(
                                color: CyberpunkTheme.neonCyan,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelDownload,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: CyberpunkTheme.neonPink
                                    .withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'ОТМЕНА',
                              style: TextStyle(
                                color: CyberpunkTheme.neonPink,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
