import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cyberpunk_theme.dart';
import '../../library/services/playlist_import_service.dart';

/// Modal dialog for importing playlists from VK, Yandex Music, or .txt files.
class ImportPlaylistDialog extends StatefulWidget {
  const ImportPlaylistDialog({super.key});

  @override
  State<ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends State<ImportPlaylistDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController =
      TextEditingController(text: 'Импортированный плейлист');
  final TextEditingController _filePathController = TextEditingController();

  final PlaylistImportService _importService = PlaylistImportService.instance;

  bool _isImporting = false;
  int _processed = 0;
  int _total = 0;
  int _recognizedCount = 0;
  String? _statusMessage;
  bool _importCompleted = false;
  bool _showHelpGuide = false;
  bool _copiedVk = false;
  bool _copiedYandex = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _textController.addListener(_updateRecognizedCount);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    _nameController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  void _updateRecognizedCount() {
    final parsed = _importService.parseRawText(_textController.text);
    if (mounted) {
      setState(() {
        _recognizedCount = parsed.length;
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        _textController.text = text;
        _updateRecognizedCount();
      }
    } catch (_) {}
  }

  Future<void> _copyVkScript() async {
    const script =
        "copy(Array.from(document.querySelectorAll('.audio_row')).map(r=>{const a=r.querySelector('.audio_row__performers a, .audio_row__performer')?.innerText?.trim()||'';const t=r.querySelector('.audio_row__title_inner')?.innerText?.trim()||'';return a&&t?a+' - '+t:''}).filter(Boolean).join('\\n'));console.log('✅ Треки VK скопированы в буфер!');";
    await Clipboard.setData(const ClipboardData(text: script));
    if (mounted) {
      setState(() => _copiedVk = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copiedVk = false);
      });
    }
  }

  Future<void> _copyYandexScript() async {
    const script =
        "copy(Array.from(document.querySelectorAll('.d-track')).map(r=>{const a=r.querySelector('.d-track__artists')?.innerText?.trim()||'';const t=r.querySelector('.d-track__title')?.innerText?.trim()||'';return a&&t?a+' - '+t:''}).filter(Boolean).join('\\n'));console.log('✅ Треки Яндекс Музыки скопированы!');";
    await Clipboard.setData(const ClipboardData(text: script));
    if (mounted) {
      setState(() => _copiedYandex = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copiedYandex = false);
      });
    }
  }

  Future<void> _pickFileOnDesktop() async {
    try {
      if (Platform.isWindows) {
        // Native OpenFileDialog on Windows without third-party dependencies
        const script =
            '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null;'
            '\$f = New-Object System.Windows.Forms.OpenFileDialog;'
            '\$f.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*";'
            '\$f.Title = "Выберите файл с треками";'
            'if (\$f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Host \$f.FileName }';

        final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
        final chosenPath = result.stdout.toString().trim();
        if (chosenPath.isNotEmpty && File(chosenPath).existsSync()) {
          _filePathController.text = chosenPath;
          final content = await File(chosenPath).readAsString();
          _textController.text = content;
          _updateRecognizedCount();
        }
      }
    } catch (_) {}
  }

  Future<void> _startImport() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isImporting) return;

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Импортированный плейлист';

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = _recognizedCount;
      _statusMessage = 'Инициализация базы данных...';
    });

    try {
      final imported = await _importService.importTracksFromText(
        text,
        playlistName: name,
        onProgress: (processed, total) {
          if (mounted) {
            setState(() {
              _processed = processed;
              _total = total;
              _statusMessage = 'Импортировано: $processed / $total';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _importCompleted = true;
          _statusMessage = 'Успешно импортировано треков: $imported';
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.of(context).pop(imported);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _statusMessage = 'Ошибка при импорте: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = ThemeController.colors.neonPrimary;
    final secondaryColor = ThemeController.colors.neonSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: GlassCard(
          borderRadius: 24,
          blur: 24,
          backgroundOpacity: 0.08,
          borderGradient: CyberpunkTheme.glassBorderGradient,
          glowColor: primaryColor,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withValues(alpha: 0.3),
                          secondaryColor.withValues(alpha: 0.15),
                        ],
                      ),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.file_download_outlined,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ИМПОРТ ИЗ VK / ЯНДЕКС МУЗЫКИ',
                          style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Автоматический парсинг списков и файлов выгрузки',
                          style: TextStyle(
                            color: CyberpunkTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Playlist Name
              TextField(
                controller: _nameController,
                enabled: !_isImporting,
                style: TextStyle(color: CyberpunkTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Название плейлиста',
                  labelStyle: TextStyle(color: primaryColor, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.03),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Tab Switcher
              Container(
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: CyberpunkTheme.violetCyanGradient,
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                  tabs: const [
                    Tab(text: 'Вставить текстом (Ctrl+V)'),
                    Tab(text: 'Выбрать .txt файл'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Body content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Text Input with Spoiler & Paste Button
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Spoiler button
                        InkWell(
                          onTap: () => setState(() => _showHelpGuide = !_showHelpGuide),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.help_outline_rounded, size: 14, color: primaryColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Как выгрузить треки из VK / Яндекс Музыки за 3 секунды',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showHelpGuide
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: primaryColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showHelpGuide) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '1. Откройте vk.com/audios в браузере (или плейлист в Яндекс Музыке).\n'
                                  '2. Нажмите F12 (или Ctrl+Shift+I) и перейдите во вкладку Console.\n'
                                  '3. Нажмите кнопку ниже, вставьте скрипт в консоль и нажмите Enter.\n'
                                  '4. Список треков сразу скопируется в буфер обмена!\n'
                                  '5. Нажмите кнопку «Вставить из буфера обмена» ниже.',
                                  style: TextStyle(
                                    color: CyberpunkTheme.textSecondary,
                                    fontSize: 11,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _copyVkScript,
                                      icon: Icon(
                                        _copiedVk ? Icons.check_rounded : Icons.code_rounded,
                                        size: 13,
                                      ),
                                      label: Text(
                                        _copiedVk
                                            ? 'СКОПИРОВАНО В БУФЕР!'
                                            : 'Скопировать JS-скрипт для VK',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor.withValues(alpha: 0.2),
                                        foregroundColor: primaryColor,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: primaryColor.withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _copyYandexScript,
                                      icon: Icon(
                                        _copiedYandex ? Icons.check_rounded : Icons.code_rounded,
                                        size: 13,
                                      ),
                                      label: Text(
                                        _copiedYandex
                                            ? 'СКОПИРОВАНО В БУФЕР!'
                                            : 'Для Яндекс Музыки',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                                        foregroundColor: Colors.white.withValues(alpha: 0.85),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            width: 0.8,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Paste from Clipboard Row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isImporting ? null : _pasteFromClipboard,
                              icon: const Icon(Icons.paste_rounded, size: 14),
                              label: const Text('📋 ВСТАВИТЬ ИЗ БУФЕРА ОБМЕНА'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.black,
                                elevation: 3,
                                shadowColor: primaryColor.withValues(alpha: 0.35),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (_textController.text.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: _isImporting
                                    ? null
                                    : () {
                                        _textController.clear();
                                        _updateRecognizedCount();
                                      },
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                label: Text(
                                  'Очистить',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Text input field
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            enabled: !_isImporting,
                            maxLines: null,
                            expands: true,
                            keyboardType: TextInputType.multiline,
                            textAlignVertical: TextAlignVertical.top,
                            style: TextStyle(
                              color: CyberpunkTheme.textPrimary,
                              fontSize: 12.5,
                              height: 1.4,
                              fontFamily: 'monospace',
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Скопируйте и вставьте список треков...\n\nПоддерживаются форматы:\n• Артист - Название\n• Артист — Название\n• Разделение табуляцией (копирование из веб-версии)\n• 1. Артист - Название (03:45)',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.28),
                                fontSize: 11.5,
                                height: 1.45,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.025),
                              contentPadding: const EdgeInsets.all(14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Tab 2: File Picker
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Выберите текстовый файл выгрузки',
                                style: TextStyle(
                                  color: CyberpunkTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Подходят файлы .txt с построчным списком треков из расширений выгрузки музыки VK или плейлистов.',
                                style: TextStyle(
                                  color: CyberpunkTheme.textMuted,
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isImporting ? null : _pickFileOnDesktop,
                                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                                    label: const Text('ВЫБРАТЬ ФАЙЛ'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.black,
                                      elevation: 4,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _filePathController.text.isNotEmpty
                                          ? _filePathController.text
                                          : 'Файл не выбран',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: CyberpunkTheme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_textController.text.isNotEmpty)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  _textController.text,
                                  style: TextStyle(
                                    color: CyberpunkTheme.textSecondary,
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Status and progress bar
              if (_isImporting) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _statusMessage ?? 'Обработка...',
                          style: TextStyle(
                            color: _importCompleted
                                ? CyberpunkTheme.neonGreen
                                : primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$_processed / $_total',
                          style: TextStyle(
                            color: CyberpunkTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _total > 0 ? (_processed / _total) : null,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Распознано треков: $_recognizedCount',
                      style: TextStyle(
                        color: _recognizedCount > 0
                            ? CyberpunkTheme.neonCyan
                            : CyberpunkTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Action button
              ElevatedButton.icon(
                onPressed: (_isImporting || _recognizedCount == 0) ? null : _startImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.bolt_rounded, size: 20, color: Colors.black),
                label: Text(
                  _isImporting
                      ? 'ИМПОРТИРУЕМ...'
                      : '⚡ НАЧАТЬ ИМПОРТ ($_recognizedCount ТРЕКОВ)',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  elevation: 8,
                  shadowColor: primaryColor.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
