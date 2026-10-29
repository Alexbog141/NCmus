import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../sync/services/cloud_sync_service.dart';
import '../../sync/workers/sync_worker.dart';

/// Cyberpunk Cloud Synchronization Screen connecting to Google Sheets endpoint.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DatabaseService _dbService = DatabaseService.instance;
  final CloudSyncService _cloudService = CloudSyncService();

  late final AnimationController _rotationController;

  bool _obscurePassword = true;
  bool _isSyncing = false;
  int _localVersion = 0;
  int _remoteVersion = -1;
  int _outboxCount = 0;
  String? _statusMessage;
  Color _statusColor = CyberpunkTheme.neonCyan;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadSavedCredentialsAndStatus();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _cloudService.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentialsAndStatus() async {
    final user = await _dbService.getSyncMeta('sync_username') ?? '';
    final pass = await _dbService.getSyncMeta('sync_password') ?? '';
    if (!mounted) return;

    _usernameController.text = user;
    _passwordController.text = pass;

    SyncWorker.instance.currentUsername = user;
    SyncWorker.instance.currentPassword = pass;

    await _refreshVersionStatus();
  }

  Future<void> _refreshVersionStatus() async {
    final localV = await _dbService.getLocalDbVersion();
    final outbox = await _dbService.getOutboxEntries();
    if (!mounted) return;

    int remoteV = -1;
    final user = _usernameController.text.trim();
    if (user.isNotEmpty) {
      remoteV = await _cloudService.checkRemoteVersion(username: user);
    }

    if (!mounted) return;
    setState(() {
      _localVersion = localV;
      _remoteVersion = remoteV;
      _outboxCount = outbox.length;
    });
  }

  Future<void> _saveCredentials() async {
    final user = _usernameController.text.trim();
    final pass = _passwordController.text.trim();

    await _dbService.setSyncMeta('sync_username', user);
    await _dbService.setSyncMeta('sync_password', pass);

    SyncWorker.instance.currentUsername = user;
    SyncWorker.instance.currentPassword = pass;

    await _refreshVersionStatus();
  }

  Future<void> _performSync() async {
    final user = _usernameController.text.trim();
    final pass = _passwordController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() {
        _statusMessage = 'Введите имя пользователя и пароль для синхронизации';
        _statusColor = CyberpunkTheme.neonPink;
      });
      return;
    }

    // Save credentials first
    await _dbService.setSyncMeta('sync_username', user);
    await _dbService.setSyncMeta('sync_password', pass);
    SyncWorker.instance.currentUsername = user;
    SyncWorker.instance.currentPassword = pass;

    setState(() {
      _isSyncing = true;
      _statusMessage = 'Синхронизация с облаком...';
      _statusColor = CyberpunkTheme.neonCyan;
    });

    _rotationController.repeat();

    try {
      final success = await SyncWorker.instance.syncNow();
      await _refreshVersionStatus();

      if (!mounted) return;
      setState(() {
        _lastSyncTime = DateTime.now();
        if (success) {
          _statusMessage = 'Синхронизация успешно выполнена!';
          _statusColor = CyberpunkTheme.neonGreen;
        } else {
          if (_outboxCount == 0 &&
              _remoteVersion != -1 &&
              _remoteVersion <= _localVersion) {
            _statusMessage = 'Все данные актуальны. Изменений нет.';
            _statusColor = CyberpunkTheme.neonCyan;
          } else {
            _statusMessage =
                'Не удалось завершить синхронизацию. Проверьте пароль или сеть.';
            _statusColor = CyberpunkTheme.neonPink;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Ошибка синхронизации: $e';
        _statusColor = CyberpunkTheme.neonPink;
      });
    } finally {
      if (mounted) {
        _rotationController.stop();
        _rotationController.reset();
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header title with neon accents
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.cloud_sync_rounded,
                      color: CyberpunkTheme.neonCyan,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CLOUD REVISION SYNC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Google Sheets / Apps Script Web App',
                        style: TextStyle(
                          color: CyberpunkTheme.neonCyan,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Status Revision Card
              GlassContainer(
                borderRadius: BorderRadius.circular(16),
                blur: 12,
                opacity: 0.08,
                borderGradient: CyberpunkTheme.glassBorderGradient,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ТЕКУЩИЙ СТАТУС РЕВИЗИИ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Icon(
                          Icons.insights_rounded,
                          color: CyberpunkTheme.neonPurple,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        // Local version
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Local Version',
                            value: 'v$_localVersion',
                            color: CyberpunkTheme.neonCyan,
                            icon: Icons.computer_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Remote version
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Remote Version',
                            value: _remoteVersion >= 0
                                ? 'v$_remoteVersion'
                                : 'Неизвестно',
                            color: CyberpunkTheme.neonPurple,
                            icon: Icons.cloud_done_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Outbox pending items
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _outboxCount > 0
                              ? CyberpunkTheme.neonAmber.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.outbox_rounded,
                                size: 18,
                                color: _outboxCount > 0
                                    ? CyberpunkTheme.neonAmber
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Локальные изменения в Outbox:',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$_outboxCount шт.',
                            style: TextStyle(
                              color: _outboxCount > 0
                                  ? CyberpunkTheme.neonAmber
                                  : Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_lastSyncTime != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Посл. синхронизация: ${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}:${_lastSyncTime!.second.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Credentials Input Form
              GlassContainer(
                borderRadius: BorderRadius.circular(16),
                blur: 12,
                opacity: 0.08,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'УЧЕТНЫЕ ДАННЫЕ СИНХРОНИЗАЦИИ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Username field
                    TextField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Имя пользователя (Google Sheets Key)',
                        labelStyle: TextStyle(color: CyberpunkTheme.neonCyan),
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: CyberpunkTheme.neonCyan,
                        ),
                      ),
                      onChanged: (_) => _refreshVersionStatus(),
                    ),

                    const SizedBox(height: 16),

                    // Password field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Пароль учетной записи',
                        labelStyle: TextStyle(color: CyberpunkTheme.neonPink),
                        prefixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: CyberpunkTheme.neonPink,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Save credentials button
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _saveCredentials,
                        icon: const Icon(Icons.save_rounded, size: 16),
                        label: const Text('Сохранить данные'),
                        style: TextButton.styleFrom(
                          foregroundColor: CyberpunkTheme.neonCyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status Message Box (if available)
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _statusColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusColor == CyberpunkTheme.neonGreen
                            ? Icons.check_circle_rounded
                            : _statusColor == CyberpunkTheme.neonPink
                                ? Icons.error_outline_rounded
                                : Icons.info_outline_rounded,
                        color: _statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Main Sync Button
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: CyberpunkTheme.cyanPinkGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isSyncing ? null : _performSync,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RotationTransition(
                        turns: _rotationController,
                        child: const Icon(
                          Icons.sync_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isSyncing
                            ? 'СИНХРОНИЗАЦИЯ...'
                            : 'СИНХРОНИЗИРОВАТЬ СЕЙЧАС',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
