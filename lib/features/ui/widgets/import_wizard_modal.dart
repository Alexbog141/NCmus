import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../library/services/import_wizard_service.dart';
import '../../library/services/playlist_url_scraper.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../scraper/providers/hitmo_provider.dart';
import '../../scraper/providers/muzofond_provider.dart';
import '../../scraper/services/mirror_resolver.dart';
import 'cyber_hud_elements.dart';

/// Cinematic 15/10 Cyberpunk Import Wizard Hub with 4-step pipeline,
/// holographic radar scanner, verification matrix, and zero-garbage staging.
class ImportWizardModal extends StatefulWidget {
  final NCPlayerHandler handler;

  const ImportWizardModal({
    super.key,
    required this.handler,
  });

  @override
  State<ImportWizardModal> createState() => _ImportWizardModalState();
}

class _ImportWizardModalState extends State<ImportWizardModal> {
  final ImportWizardService _wizard = ImportWizardService.instance;
  late final ScraperEngine _scraperEngine;

  int _currentStep = 0; // 0: Intake, 1: Radar, 2: Matrix, 3: Final
  int _intakeSourceIndex = 0; // 0: Link, 1: Clipboard, 2: File
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController =
      TextEditingController(text: 'Импортированная коллекция');
  final TextEditingController _filePathController = TextEditingController();

  bool _isUrlLoading = false;
  String? _urlError;

  StreamSubscription<ImportScanProgress>? _scanSub;
  ImportScanProgress _scanProgress = const ImportScanProgress(
    processed: 0,
    total: 0,
    currentQuery: '',
    exactCount: 0,
    disputedCount: 0,
    notFoundCount: 0,
  );

  int _matrixTabIndex = 0; // 0: Ready, 1: Disputed, 2: Missing
  bool _showQuickGuide = false;
  bool _copiedVk = false;
  bool _isCommitting = false;
  int _committedCount = 0;

  @override
  void initState() {
    super.initState();
    // Zero-garbage guarantee on entry
    unawaited(_wizard.wipeStagingSession());

    _scraperEngine = ScraperEngine(
      providers: [
        HitmoProvider(mirrorResolver: MirrorResolver()),
        MuzofondProvider(mirrorResolver: MirrorResolver()),
      ],
    );

    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _urlController.dispose();
    _textController.dispose();
    _nameController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_currentStep == 0) {
      _wizard.parseRawInput(_textController.text);
      if (mounted) setState(() {});
    }
  }

  Future<void> _cancelAndExit() async {
    await _wizard.wipeStagingSession();
    if (mounted) {
      Navigator.of(context).pop(_committedCount);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _textController.text = text;
        if (text.startsWith('http://') || text.startsWith('https://')) {
          _urlController.text = text;
        }
        _wizard.parseRawInput(text);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _pasteLinkFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _urlController.text = text;
        if (mounted) {
          setState(() {
            _urlError = null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _scanPlaylistUrl() async {
    var rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _urlError = 'Введите ссылку на плейлист';
      });
      return;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    setState(() {
      _isUrlLoading = true;
      _urlError = null;
    });

    try {
      final tracks = await PlaylistUrlScraper.fetchTracksFromUrl(rawUrl);
      if (!mounted) return;

      if (tracks.isEmpty) {
        throw Exception(
            'Не удалось извлечь треки. Убедитесь, что плейлист открыт для всех в настройках приватности.');
      }

      // 1. Заполняем список распознанных треков мастера
      final buffer = StringBuffer();
      for (final t in tracks) {
        buffer.writeln(t.toFormattedLine());
      }
      final formattedText = buffer.toString().trim();
      _textController.text = formattedText;
      _wizard.parseRawInput(formattedText);

      // 2. Заполняем название плейлиста по умолчанию (если удалось определить)
      final detectedTitle = PlaylistUrlScraper.lastDetectedPlaylistTitle;
      if (detectedTitle != null && detectedTitle.trim().isNotEmpty) {
        _nameController.text = detectedTitle.trim();
      }

      setState(() {
        _isUrlLoading = false;
        _urlError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _isUrlLoading = false;
        _urlError = msg;
      });
    }
  }

  Future<void> _pickFileOnDesktop() async {
    try {
      if (Platform.isWindows) {
        const script =
            '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null;'
            '\$f = New-Object System.Windows.Forms.OpenFileDialog;'
            '\$f.Filter = "Text & CSV files (*.txt;*.csv)|*.txt;*.csv|All files (*.*)|*.*";'
            '\$f.Title = "Выберите файл выгрузки треков";'
            'if (\$f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Host \$f.FileName }';

        final result =
            await Process.run('powershell', ['-NoProfile', '-Command', script]);
        final chosenPath = result.stdout.toString().trim();
        if (chosenPath.isNotEmpty && File(chosenPath).existsSync()) {
          _filePathController.text = chosenPath;
          final content = await File(chosenPath).readAsString();
          _textController.text = content;
          _wizard.parseRawInput(content);
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _copyVkScript() async {
    const script =
        "copy(Array.from(document.querySelectorAll('.audio_row')).map(r=>{const a=r.querySelector('.audio_row__performers a, .audio_row__performer')?.innerText?.trim()||'';const t=r.querySelector('.audio_row__title_inner')?.innerText?.trim()||'';return a&&t?a+' - '+t:''}).filter(Boolean).join('\\n'));console.log('✅ Музыка VK скопирована в буфер!');";
    await Clipboard.setData(const ClipboardData(text: script));
    if (mounted) {
      setState(() => _copiedVk = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copiedVk = false);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Pipeline Step Transitions
  // ---------------------------------------------------------------------------
  void _startRadarScan() {
    if (_wizard.totalCount == 0) return;

    setState(() {
      _currentStep = 1;
    });

    _scanSub?.cancel();
    _scanSub =
        _wizard.startScan(scraperEngine: _scraperEngine).listen((progress) {
      if (mounted) {
        setState(() {
          _scanProgress = progress;
        });
      }
    }, onDone: () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _proceedToVerificationMatrix() {
    setState(() {
      _currentStep = 2;
    });
  }

  Future<void> _commitAndFinalize() async {
    setState(() => _isCommitting = true);
    final count = await _wizard.commitToLibrary(
      playlistName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'Импортированная коллекция',
    );
    if (mounted) {
      setState(() {
        _committedCount = count;
        _isCommitting = false;
        _currentStep = 3; // Step 4: Final
      });
    }
  }

  Future<void> _exportMissingTracks() async {
    final report = _wizard.generateMissingTracksReport();
    await Clipboard.setData(ClipboardData(text: report));

    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        final outPath = '$userProfile\\Downloads\\missing_tracks.txt';
        await File(outPath).writeAsString(report);
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Список отсутствующих треков скопирован в буфер и сохранен в Downloads!',
            style: TextStyle(color: CyberpunkTheme.neonCyan),
          ),
          backgroundColor: CyberpunkTheme.cardColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final primary = ThemeController.colors.neonPrimary;
    final secondary = ThemeController.colors.neonSecondary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancelAndExit();
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 730),
          child: GlassCard(
            borderRadius: 24,
            blur: 30,
            backgroundOpacity: 0.08,
            borderGradient: CyberpunkTheme.glassBorderGradient,
            glowColor: primary,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(primary, secondary),
                const SizedBox(height: 14),
                CyberStepPipeline(
                  currentStep: _currentStep,
                  onStepTapped: (index) {
                    if (index < _currentStep) {
                      setState(() => _currentStep = index);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _buildCurrentStepView(primary, secondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color primary, Color secondary) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                primary.withValues(alpha: 0.3),
                secondary.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(
              color: primary.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'КИБЕР-МАСТЕР ИМПОРТА // IMPORT WIZARD',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Интеллектуальная верификация и кросс-поиск аудиопотоков',
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _cancelAndExit,
          icon: Icon(
            Icons.close_rounded,
            color: Colors.white.withValues(alpha: 0.6),
            size: 22,
          ),
          splashRadius: 18,
          tooltip: 'Закрыть и сбросить сессию',
        ),
      ],
    );
  }

  Widget _buildCurrentStepView(Color primary, Color secondary) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Intake(primary, secondary);
      case 1:
        return _buildStep2Radar(primary, secondary);
      case 2:
        return _buildStep3Matrix(primary, secondary);
      case 3:
      default:
        return _buildStep4Final(primary, secondary);
    }
  }

  // ===========================================================================
  // ШАГ 1: ВХОДНЫЕ ДАННЫЕ (SOURCE INTAKE)
  // ===========================================================================
  Widget _buildStep1Intake(Color primary, Color secondary) {
    final trackCount = _wizard.totalCount;

    return SingleChildScrollView(
      key: const ValueKey('step_1_intake'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 3 чёткие кнопки выбора источника в шапке 01 ВХОД
          Row(
            children: [
              _buildSourceTabButton(
                index: 0,
                label: '🔗 Ссылка на плейлист',
                primary: primary,
              ),
              const SizedBox(width: 8),
              _buildSourceTabButton(
                index: 1,
                label: '📋 Буфер обмена',
                primary: primary,
              ),
              const SizedBox(width: 8),
              _buildSourceTabButton(
                index: 2,
                label: '📁 Файл .txt',
                primary: primary,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Содержимое активного источника
          if (_intakeSourceIndex == 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primary.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link_rounded, color: primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'ВХОД ПО ССЫЛКЕ НА ПЛЕЙЛИСТ',
                        style: TextStyle(
                          color: primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Поле ввода TextField с неоновой окантовкой:
                  // - Хинт: "https://vk.com/music/playlist/... или https://music.yandex.ru/..."
                  // - Иконка ссылки Icons.link_rounded
                  // - Кнопка быстрой вставки из системного буфера обмена (Icons.content_paste_rounded)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primary.withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, color: primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            enabled: !_isUrlLoading,
                            style: TextStyle(
                              color: CyberpunkTheme.textPrimary,
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText:
                                  'https://vk.com/music/playlist/... или https://music.yandex.ru/...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11.5,
                              ),
                            ),
                            onSubmitted: (_) => _scanPlaylistUrl(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed:
                              _isUrlLoading ? null : _pasteLinkFromClipboard,
                          icon: const Icon(Icons.content_paste_rounded,
                              size: 14, color: Colors.black),
                          label: const Text(
                            'ВСТАВИТЬ',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            disabledBackgroundColor:
                                primary.withValues(alpha: 0.3),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Неоновая кнопка действия [ ⚡ СКАНИРОВАТЬ ССЫЛКУ ]
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isUrlLoading ? null : _scanPlaylistUrl,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        disabledBackgroundColor:
                            primary.withValues(alpha: 0.35),
                        elevation: 6,
                        shadowColor: primary.withValues(alpha: 0.45),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isUrlLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.black),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Считываем плейлист...',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt_rounded,
                                    size: 18, color: Colors.black),
                                SizedBox(width: 6),
                                Text(
                                  '⚡ СКАНИРОВАТЬ ССЫЛКУ',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  // Предупреждающая стеклянная плашка красного/неонового цвета с текстом ошибки
                  if (_urlError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.6),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _urlError!,
                              style: const TextStyle(
                                color: Color(0xFFFF8A80),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_intakeSourceIndex == 1) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded,
                    size: 18, color: Colors.black),
                label: const Text(
                  '📋 ВСТАВИТЬ ИЗ БУФЕРА ОБМЕНА',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  elevation: 6,
                  shadowColor: primary.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickFileOnDesktop,
                icon: const Icon(Icons.folder_open_rounded,
                    size: 18, color: Colors.black),
                label: Text(
                  _filePathController.text.isNotEmpty
                      ? '📁 ФАЙЛ: ${_filePathController.text.split(Platform.isWindows ? r'\' : '/').last} (ВЫБРАТЬ ДРУГОЙ)'
                      : '📁 ВЫБРАТЬ ФАЙЛ ВЫГРУЗКИ (.TXT / .CSV)',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  elevation: 6,
                  shadowColor: primary.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Spoiler: VK / Yandex Quick Script Guide
          InkWell(
            onTap: () => setState(() => _showQuickGuide = !_showQuickGuide),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: primary.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Как выгрузить треки из VK / Яндекс Музыки за 3 секунды',
                      style: TextStyle(
                        color: primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _showQuickGuide
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: primary,
                  ),
                ],
              ),
            ),
          ),
          if (_showQuickGuide) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Откройте vk.com/audios или плейлист в браузере.\n'
                    '2. Нажмите F12 (или Ctrl+Shift+I) и выберите вкладку Console.\n'
                    '3. Нажмите кнопку ниже, вставьте скрипт в консоль и нажмите Enter.\n'
                    '4. Список всех треков моментально скопируется в буфер обмена!\n'
                    '5. Нажмите кнопку «📋 Вставить из буфера» выше.',
                    style: TextStyle(
                      color: CyberpunkTheme.textSecondary,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _copyVkScript,
                    icon: Icon(
                        _copiedVk ? Icons.check_rounded : Icons.code_rounded,
                        size: 14),
                    label: Text(_copiedVk
                        ? 'СКОПИРОВАНО В БУФЕР!'
                        : 'Скопировать JS-скрипт для VK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary.withValues(alpha: 0.2),
                      foregroundColor: primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                            color: primary.withValues(alpha: 0.4), width: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Playlist Name Field
          TextField(
            controller: _nameController,
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              prefixText: '> PLAYLIST_NAME:  ',
              prefixStyle: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primary, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Input Text Box
          SizedBox(
            height: 140,
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 12,
                height: 1.4,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText:
                    'Вставьте список треков...\nПример:\nThe Prodigy - Breathe (05:35)\nDaft Punk — Get Lucky\nKavinsky\tNightcall',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 11.5,
                  height: 1.45,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.025),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primary, width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bottom Bar: Counter Card & Launch Radar Button
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: trackCount > 0
                        ? primary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'ОБНАРУЖЕНО ТРЕКОВ: ',
                      style: TextStyle(
                        color: CyberpunkTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$trackCount',
                      style: TextStyle(
                        color: trackCount > 0
                            ? primary
                            : Colors.white.withValues(alpha: 0.4),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: trackCount > 0 ? _startRadarScan : null,
                icon: const Icon(Icons.radar_rounded,
                    size: 18, color: Colors.black),
                label: Text(
                  '⚡ ЗАПУСТИТЬ КИБЕР-СКАНЕР ($trackCount)',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  elevation: 8,
                  shadowColor: primary.withValues(alpha: 0.5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTabButton({
    required int index,
    required String label,
    required Color primary,
  }) {
    final isSelected = _intakeSourceIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _intakeSourceIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected ? primary : Colors.white.withValues(alpha: 0.09),
              width: isSelected ? 1.4 : 0.6,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.6),
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ШАГ 2: АНИМИРОВАННЫЙ КИБЕР-РАДАР (HOLOGRAPHIC SCAN)
  // ===========================================================================
  Widget _buildStep2Radar(Color primary, Color secondary) {
    final isDone = !_wizard.isScanning &&
        _scanProgress.processed >= _scanProgress.total &&
        _scanProgress.total > 0;

    return Column(
      key: const ValueKey('step_2_radar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            children: [
              // Radar in Center
              Expanded(
                flex: 5,
                child: CyberRadarScanner(
                  size: 210,
                  color: primary,
                  isScanning: _wizard.isScanning,
                  statusText: _wizard.isScanning
                      ? 'SCANNING: ${_scanProgress.currentQuery.toUpperCase()}'
                      : 'SCAN COMPLETE · READY FOR MATRIX',
                ),
              ),

              // 3 Floating Telemetry Cards
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TelemetryStatCard(
                      label: 'СОВПАДЕНИЯ 100%',
                      badge: 'Δ <= 2s',
                      count: _scanProgress.exactCount,
                      color: CyberpunkTheme.neonGreen,
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _TelemetryStatCard(
                      label: 'СПОРНЫЕ',
                      badge: 'Каверы / Δ > 2s',
                      count: _scanProgress.disputedCount,
                      color: CyberpunkTheme.neonAmber,
                      icon: Icons.warning_amber_rounded,
                    ),
                    const SizedBox(height: 12),
                    _TelemetryStatCard(
                      label: 'НЕ НАЙДЕНО',
                      badge: 'Эксклюзивы',
                      count: _scanProgress.notFoundCount,
                      color: CyberpunkTheme.neonPink,
                      icon: Icons.cancel_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Shimmer progress bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ПРОГРЕСС СКАНИРОВАНИЯ: ${_scanProgress.processed} / ${_scanProgress.total}',
              style: TextStyle(
                color: CyberpunkTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '${(_scanProgress.ratio * 100).toInt()}%',
              style: TextStyle(
                color: primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CyberShimmerProgressBar(
          progress: _scanProgress.ratio,
          color: primary,
          secondaryColor: secondary,
          height: 8,
        ),
        const SizedBox(height: 14),

        // Proceed Button
        ElevatedButton.icon(
          onPressed: isDone ? _proceedToVerificationMatrix : null,
          icon: const Icon(Icons.fact_check_rounded,
              size: 18, color: Colors.black),
          label: Text(
            isDone
                ? '⚡ ПЕРЕЙТИ В ЦЕНТР ВЕРИФИКАЦИИ'
                : 'СКАНИРУЕМ СЕТЕВЫЕ ИСТОЧНИКИ...',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDone ? primary : Colors.white.withValues(alpha: 0.15),
            elevation: isDone ? 8 : 0,
            shadowColor: primary.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ШАГ 3: ЦЕНТР ВЕРИФИКАЦИИ И РАЗРЕШЕНИЯ СПОРОВ (VERIFICATION MATRIX)
  // ===========================================================================
  Widget _buildStep3Matrix(Color primary, Color secondary) {
    final readyTracks = _wizard.stagedMatches
        .where((m) => m.status == ImportMatchStatus.exactMatch)
        .toList();
    final disputedTracks = _wizard.stagedMatches
        .where((m) => m.status == ImportMatchStatus.disputed)
        .toList();
    final missingTracks = _wizard.stagedMatches
        .where((m) => m.status == ImportMatchStatus.notFound)
        .toList();

    return Column(
      key: const ValueKey('step_3_matrix'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab switchers
        Row(
          children: [
            _MatrixTabButton(
              title: 'ГОТОВЫ (${readyTracks.length})',
              color: CyberpunkTheme.neonGreen,
              isSelected: _matrixTabIndex == 0,
              onTap: () => setState(() => _matrixTabIndex = 0),
            ),
            const SizedBox(width: 8),
            _MatrixTabButton(
              title: 'ТРЕБУЮТ ВНИМАНИЯ (${disputedTracks.length})',
              color: CyberpunkTheme.neonAmber,
              isSelected: _matrixTabIndex == 1,
              onTap: () => setState(() => _matrixTabIndex = 1),
            ),
            const SizedBox(width: 8),
            _MatrixTabButton(
              title: 'НЕ НАЙДЕНЫ (${missingTracks.length})',
              color: CyberpunkTheme.neonPink,
              isSelected: _matrixTabIndex == 2,
              onTap: () => setState(() => _matrixTabIndex = 2),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // List body
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06), width: 0.5),
            ),
            child: _buildMatrixTabContent(
                readyTracks, disputedTracks, missingTracks, primary),
          ),
        ),
        const SizedBox(height: 12),

        // Floating Action Bottom Bar
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Второстепенное действие (Компактная кнопка экспорта)
              if (missingTracks.isNotEmpty)
                Tooltip(
                  message: 'Скачать список ненайденных треков в .txt',
                  child: OutlinedButton.icon(
                    onPressed: _exportMissingTracks,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('ОТЧЁТ .TXT',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CyberpunkTheme.neonPink,
                      side: BorderSide(
                          color:
                              CyberpunkTheme.neonPink.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

              const Spacer(),

              // Главная акцентная кнопка (Неоновый пилл без переполнения)
              ElevatedButton.icon(
                onPressed: (_isCommitting || readyTracks.isEmpty)
                    ? null
                    : _commitAndFinalize,
                icon: _isCommitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.bolt_rounded,
                        size: 18, color: Colors.black),
                label: Text(
                  'ПЕРЕНЕСТИ В МЕДИАТЕКУ (${readyTracks.length})',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberpunkTheme.neonGreen,
                  elevation: 6,
                  shadowColor: CyberpunkTheme.neonGreen.withValues(alpha: 0.4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatrixTabContent(
    List<ImportTrackMatch> ready,
    List<ImportTrackMatch> disputed,
    List<ImportTrackMatch> missing,
    Color primary,
  ) {
    if (_matrixTabIndex == 0) {
      if (ready.isEmpty) {
        return const Center(
          child: Text('Нет готовых треков для переноса.',
              style: TextStyle(color: Colors.white54)),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: ready.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final item = ready[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: CyberpunkTheme.neonGreen, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.candidate?.title ?? item.originalTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      Text(
                        item.candidate?.artist ?? item.originalArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CyberpunkTheme.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.deltaBadgeText,
                    style: TextStyle(
                        color: CyberpunkTheme.neonGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_matrixTabIndex == 1) {
      if (disputed.isEmpty) {
        return Center(
          child: Text('Все конфликты разрешены! Все треки подтверждены.',
              style: TextStyle(color: CyberpunkTheme.neonGreen)),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: disputed.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = disputed[i];
          final candidate = item.candidate;

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: CyberpunkTheme.neonAmber.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Original VK Track
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('ОРИГИНАЛ VK',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          if (item.originalDuration != null)
                            Text(
                              '${item.originalDuration!.inMinutes}:${(item.originalDuration!.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  color: CyberpunkTheme.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'monospace'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.originalTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.originalArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: Colors.white30),
                const SizedBox(width: 8),

                // Right: Scraped candidate
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: CyberpunkTheme.neonAmber
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('НАЙДЕНО В СЕТИ',
                                style: TextStyle(
                                    color: CyberpunkTheme.neonAmber,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: (item.deltaSeconds <= 2
                                      ? CyberpunkTheme.neonGreen
                                      : CyberpunkTheme.neonPink)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.deltaBadgeText,
                              style: TextStyle(
                                color: item.deltaSeconds <= 2
                                    ? CyberpunkTheme.neonGreen
                                    : CyberpunkTheme.neonPink,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        candidate?.title ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        candidate?.artist ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CyberpunkTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // 5s Audio Wave Preview
                MiniAudioWavePreview(
                  track: candidate,
                  handler: widget.handler,
                ),
                const SizedBox(width: 10),

                // Choose Button
                ElevatedButton(
                  onPressed: candidate != null
                      ? () {
                          setState(() {
                            _wizard.resolveDispute(item.id, candidate);
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberpunkTheme.neonGreen,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('ВЫБРАТЬ',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                ),
              ],
            ),
          );
        },
      );
    }

    // Tab 2: Missing
    if (missing.isEmpty) {
      return Center(
        child: Text('Все треки найдены в сети!',
            style: TextStyle(color: CyberpunkTheme.neonGreen)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: missing.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final item = missing[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Icon(Icons.cancel_outlined,
                  color: CyberpunkTheme.neonPink, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${item.originalArtist} — ${item.originalTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: CyberpunkTheme.textPrimary, fontSize: 12.5),
                ),
              ),
              Text('Не найдено',
                  style: TextStyle(
                      color: CyberpunkTheme.neonPink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // ШАГ 4: ФИНАЛ И ПОЛНАЯ САМООЧИСТКА (CLEAN TERMINATION)
  // ===========================================================================
  Widget _buildStep4Final(Color primary, Color secondary) {
    return Center(
      key: const ValueKey('step_4_final'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  LinearGradient(colors: [primary, CyberpunkTheme.neonGreen]),
              boxShadow: [
                BoxShadow(
                    color: CyberpunkTheme.neonGreen.withValues(alpha: 0.5),
                    blurRadius: 28,
                    spreadRadius: 3),
              ],
            ),
            child: const Center(
              child: Icon(Icons.check_rounded, color: Colors.black, size: 44),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'ИМПОРТ УСПЕШНО ЗАВЕРШЁН!',
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'МЕДИАТЕКА ОБНОВЛЕНА · ВСЕ ВРЕМЕННЫЕ ДАННЫЕ ОЧИЩЕНЫ',
            style: TextStyle(
              color: CyberpunkTheme.neonGreen,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Добавлено новых треков в медиатеку: $_committedCount',
            style: TextStyle(color: CyberpunkTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(_committedCount),
            icon: const Icon(Icons.headphones_rounded,
                size: 18, color: Colors.black),
            label: const Text(
              'ПЕРЕЙТИ К ПРОСЛУШИВАНИЮ',
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              elevation: 8,
              shadowColor: primary.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Private Custom Card Widgets
// -----------------------------------------------------------------------------
class _TelemetryStatCard extends StatelessWidget {
  final String label;
  final String badge;
  final int count;
  final Color color;
  final IconData icon;

  const _TelemetryStatCard({
    required this.label,
    required this.badge,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 10,
              spreadRadius: 0.5),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      color: CyberpunkTheme.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  badge,
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _MatrixTabButton extends StatelessWidget {
  final String title;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _MatrixTabButton({
    required this.title,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.0 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.25), blurRadius: 10),
                  ]
                : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
