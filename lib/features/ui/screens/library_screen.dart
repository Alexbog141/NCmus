import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../library/services/local_storage_service.dart';
import '../../storage/models/track_entity.dart';
import '../../wave/services/wave_service.dart';
import '../widgets/cyber_visualizer.dart';
import '../widgets/import_wizard_modal.dart';
import '../widgets/batch_download_dialog.dart';
import '../../storage/models/playlist_entity.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/create_playlist_dialog.dart';
import 'playlist_detail_screen.dart';

/// Library with glass tabs for favourites and local downloads.
class LibraryScreen extends StatefulWidget {
  final NCPlayerHandler handler;

  const LibraryScreen({
    super.key,
    required this.handler,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibrarySortMode {
  dateDesc('Сначала новые'),
  titleAsc('По названию (А–Я)'),
  artistAsc('По артисту');

  final String label;
  const _LibrarySortMode(this.label);
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final DatabaseService _dbService = DatabaseService.instance;

  StreamSubscription<void>? _librarySubscription;

  List<TrackEntity> _downloadedTracks = <TrackEntity>[];
  List<TrackEntity> _favoriteTracks = <TrackEntity>[];
  List<Map<String, dynamic>> _historyTracks = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _topArtists = <Map<String, dynamic>>[];
  List<PlaylistEntity> _playlists = <PlaylistEntity>[];
  final Set<String> _favoriteBusy = <String>{};
  bool _isLoading = true;
  bool _isScanningLocal = false;
  int _loadGeneration = 0;

  // Favorites toolbar state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _tabsScrollController = ScrollController();
  final Map<int, GlobalKey> _tabKeys = <int, GlobalKey>{
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
    4: GlobalKey(),
  };
  PlaylistEntity? _selectedPlaylist;
  String _searchQuery = '';
  bool _onlyOffline = false;
  _LibrarySortMode _sortMode = _LibrarySortMode.dateDesc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
        if (!_tabController.indexIsChanging) {
          final keyContext = _tabKeys[_tabController.index]?.currentContext;
          if (keyContext != null) {
            Scrollable.ensureVisible(
              keyContext,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: 0.5,
            );
          }
        }
      }
    });
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _librarySubscription =
        _dbService.libraryChanges.listen((_) => _loadTracks());
    _loadTracks();
  }

  void _onTabTapped(int index) {
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
    setState(() {});
    final keyContext = _tabKeys[index]?.currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.5, // 0.5 центрирует элемент ровно посередине строки
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabsScrollController.dispose();
    _librarySubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTracks({bool showSpinner = false}) async {
    final generation = ++_loadGeneration;

    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _dbService.getFavoriteTracks(),
        _dbService.getAllDownloadedTracks(),
        _dbService.getListeningHistory(limit: 50),
        _dbService.getTopArtistsWithTracks(limit: 10),
        _dbService.getPlaylists(),
      ]);

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _favoriteTracks = results[0] as List<TrackEntity>;
        _downloadedTracks = results[1] as List<TrackEntity>;
        _historyTracks = results[2] as List<Map<String, dynamic>>;
        _topArtists = results[3] as List<Map<String, dynamic>>;
        _playlists = results[4] as List<PlaylistEntity>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncLocalTracks() async {
    if (_isScanningLocal) return;
    setState(() => _isScanningLocal = true);
    try {
      await LocalStorageService.instance.scanAndSyncLocalFolder();
      await _loadTracks(showSpinner: false);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isScanningLocal = false);
      }
    }
  }

  Future<void> _openImportDialog(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportWizardModal(handler: widget.handler),
    );
    if (result != null && result > 0) {
      await _loadTracks(showSpinner: true);
    }
  }

  Future<void> _openBatchDownloadDialog(
      BuildContext context, List<TrackEntity> tracks) async {
    if (tracks.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BatchDownloadDialog(tracks: tracks),
    );
    await _loadTracks(showSpinner: false);
  }

  Future<void> _purgeGhostTracks() async {
    try {
      final purged = await _dbService.purgeZeroDurationGhostTracks();
      await _loadTracks(showSpinner: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            purged > 0
                ? 'Очищено треков-пустышек: $purged'
                : 'Треков-пустышек (00:00) не обнаружено',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor:
              purged > 0 ? CyberpunkTheme.neonGreen : const Color(0xFF141A29),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при очистке: $e'),
          backgroundColor: CyberpunkTheme.neonPink,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------
  Future<void> _playTrackAt(List<TrackEntity> tracks, int index) async {
    if (tracks.isEmpty) return;

    try {
      WaveService.instance.stopWave();
      final items = tracks.map((track) => track.toMediaItem()).toList();
      await widget.handler
          .setQueueAndPlay(items, index.clamp(0, items.length - 1).toInt());
    } catch (error) {
      if (!mounted) return;
      _showMessage('Ошибка воспроизведения: $error', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Favourites and downloads
  // ---------------------------------------------------------------------------
  Future<void> _toggleFavorite(TrackEntity track) async {
    if (_favoriteBusy.contains(track.id)) return;

    final nextValue = !track.isFavorite;

    setState(() {
      _favoriteBusy.add(track.id);
      _downloadedTracks = _downloadedTracks
          .map((item) =>
              item.id == track.id ? item.copyWith(isFavorite: nextValue) : item)
          .toList();

      if (nextValue) {
        _favoriteTracks = [
          track.copyWith(isFavorite: true),
          ..._favoriteTracks.where((item) => item.id != track.id),
        ];
      } else {
        _favoriteTracks =
            _favoriteTracks.where((item) => item.id != track.id).toList();
      }
    });

    try {
      await _dbService.toggleFavorite(track.id, nextValue);
    } catch (error) {
      if (!mounted) return;
      await _loadTracks();
      _showMessage('Не удалось обновить избранное: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy.remove(track.id);
        });
      }
    }
  }

  Future<void> _removeDownload(TrackEntity track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CyberpunkTheme.cardColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.09),
              width: 0.5,
            ),
          ),
          title: Text(
            'Удалить с устройства?',
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Локальная копия «${track.title}» будет удалена. '
            'Трек останется в избранном, если вы его отметили.',
            style: TextStyle(
              color: CyberpunkTheme.textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'ОТМЕНА',
                style: TextStyle(color: CyberpunkTheme.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'УДАЛИТЬ',
                style: TextStyle(
                  color: CyberpunkTheme.neonPink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final localPath = track.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      try {
        final file = File(localPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // Removing the DB row is still useful even if the file is locked.
      }
    }

    try {
      await _dbService.removeDownload(track.id);

      // A downloaded-only track should disappear completely once its file is
      // gone. Favourites stay in the library as streaming entries.
      if (!track.isFavorite) {
        await _dbService.deleteTrack(track.id);
      }

      await _loadTracks();
      if (!mounted) return;
      _showMessage('Локальная копия удалена');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Не удалось удалить файл: $error', isError: true);
    }
  }

  void _openInExplorer(String? filePath) {
    if (filePath == null || filePath.isEmpty) return;

    final file = File(filePath);
    if (Platform.isWindows) {
      if (file.existsSync()) {
        Process.run('explorer.exe', ['/select,', filePath]);
      } else if (file.parent.existsSync()) {
        Process.run('explorer.exe', [file.parent.path]);
      }
    } else if (Platform.isMacOS) {
      if (file.existsSync()) {
        Process.run('open', ['-R', filePath]);
      }
    } else if (Platform.isLinux) {
      if (file.parent.existsSync()) {
        Process.run('xdg-open', [file.parent.path]);
      }
    }
  }

  bool _hasLocalFile(TrackEntity track) {
    final localPath = track.localPath;
    if (localPath == null || localPath.isEmpty) return false;
    return File(localPath).existsSync();
  }

  bool _isCurrentTrack(MediaItem? current, TrackEntity track) {
    if (current == null) return false;
    if (current.extras?['originalId'] == track.id) return true;
    if (current.id == track.streamUrl) return true;
    if (track.localPath != null && current.id == track.localPath) return true;
    return false;
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showMessage(String message, {bool isError = false}) {
    // Snackbars disabled across the application to prevent blocking the player bar
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedPlaylist == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedPlaylist != null) {
          _closePlaylistDetail();
        }
      },
      child: Focus(
        autofocus: _selectedPlaylist != null,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              _selectedPlaylist != null) {
            _closePlaylistDetail();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Column(
              children: [
                Opacity(
                  opacity: 0.0,
                  child: SizedBox(
                    height: 0.0,
                    width: 0.0,
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(child: SizedBox.shrink()),
                        Tab(child: SizedBox.shrink()),
                        Tab(child: SizedBox.shrink()),
                        Tab(child: SizedBox.shrink()),
                        Tab(child: SizedBox.shrink()),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlassCard(
                          borderRadius: 16,
                          blur: 16,
                          backgroundOpacity: 0.04,
                          borderGradient: CyberpunkTheme.glassBorderGradientSoft,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Listener(
                            onPointerSignal: (pointerSignal) {
                              if (pointerSignal is PointerScrollEvent) {
                                if (_tabsScrollController.hasClients) {
                                  // Если крутят колесо мыши — берем dy. Если свайпают тачпад по горизонтали — берем dx:
                                  final double delta = pointerSignal.scrollDelta.dx != 0
                                      ? pointerSignal.scrollDelta.dx
                                      : pointerSignal.scrollDelta.dy;

                                  final double newOffset = (_tabsScrollController.offset +
                                          delta)
                                      .clamp(
                                          0.0,
                                          _tabsScrollController
                                              .position.maxScrollExtent);
                                  _tabsScrollController.jumpTo(newOffset);
                                }
                              }
                            },
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: SingleChildScrollView(
                                controller: _tabsScrollController,
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTabChip(
                              index: 0,
                              icon: Icons.favorite_rounded,
                              label: 'Избранное (${_favoriteTracks.length})',
                            ),
                            const SizedBox(width: 6),
                            _buildTabChip(
                              index: 1,
                              icon: Icons.playlist_play_rounded,
                              label: 'Плейлисты (${_playlists.length})',
                            ),
                            const SizedBox(width: 6),
                            _buildTabChip(
                              index: 2,
                              icon: Icons.download_done_rounded,
                              label: 'Загрузки (${_downloadedTracks.length})',
                            ),
                            const SizedBox(width: 6),
                            _buildTabChip(
                              index: 3,
                              icon: Icons.history_rounded,
                              label: 'История (${_historyTracks.length})',
                            ),
                            const SizedBox(width: 6),
                            _buildTabChip(
                              index: 4,
                              icon: Icons.leaderboard_rounded,
                              label: 'Топ артистов',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Top bar button: + Новый плейлист in Cyberpunk neon style
              GlassCard(
                borderRadius: 14,
                blur: 14,
                backgroundOpacity: 0.08,
                borderGradient: CyberpunkTheme.glassBorderGradient,
                glowColor: CyberpunkTheme.neonCyan,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                onTap: _openCreatePlaylistDialog,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: CyberpunkTheme.neonCyan,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Новый плейлист',
                      style: TextStyle(
                        color: CyberpunkTheme.neonCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GlassCard(
                borderRadius: 14,
                blur: 14,
                backgroundOpacity: 0.04,
                borderGradient: CyberpunkTheme.glassBorderGradientSoft,
                padding: EdgeInsets.zero,
                child: IconButton(
                  onPressed: () => _openImportDialog(context),
                  icon: Icon(
                    Icons.file_download_outlined,
                    color: CyberpunkTheme.neonCyan,
                    size: 20,
                  ),
                  tooltip: 'Импорт из VK / Яндекс Музыки',
                  splashRadius: 18,
                ),
              ),
              const SizedBox(width: 8),
              GlassCard(
                borderRadius: 14,
                blur: 14,
                backgroundOpacity: 0.04,
                borderGradient: CyberpunkTheme.glassBorderGradientSoft,
                padding: EdgeInsets.zero,
                child: IconButton(
                  onPressed: _syncLocalTracks,
                  icon: _isScanningLocal
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CyberpunkTheme.neonCyan,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          color: CyberpunkTheme.neonCyan,
                          size: 20,
                        ),
                  tooltip: 'Обновить локальные треки (Music/NCmus)',
                  splashRadius: 18,
                ),
              ),
              const SizedBox(width: 8),
              GlassCard(
                borderRadius: 14,
                blur: 14,
                backgroundOpacity: 0.04,
                borderGradient: CyberpunkTheme.glassBorderGradientSoft,
                padding: EdgeInsets.zero,
                child: IconButton(
                  onPressed: _purgeGhostTracks,
                  icon: Icon(
                    Icons.cleaning_services_rounded,
                    color: CyberpunkTheme.neonPink,
                    size: 20,
                  ),
                  tooltip: 'Очистить треки-пустышки (00:00)',
                  splashRadius: 18,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: CyberpunkTheme.neonCyan,
                    strokeWidth: 2,
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFavoritesTab(),
                    _buildPlaylistsTab(),
                    _buildTrackList(
                      tracks: _downloadedTracks,
                      emptyIcon: Icons.download_for_offline_rounded,
                      emptyTitle: 'НЕТ ЛОКАЛЬНЫХ ТРЕКОВ',
                      emptySubtitle:
                          'Скачайте музыку из поиска или сохраняйте любимые треки.',
                    ),
                    _buildHistoryList(),
                    _buildTopArtistsList(),
                  ],
                ),
        ),
        Offstage(
          offstage: true,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Избранное'),
              Tab(text: 'Плейлисты'),
              Tab(text: 'Загрузки'),
              Tab(text: 'История'),
              Tab(text: 'Топ артистов'),
            ],
          ),
        ),
      ],
    ),
    if (_selectedPlaylist != null) ...[
      // Semi-transparent blur layer
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closePlaylistDetail,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
      // Compact floating playlist card
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closePlaylistDetail,
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Prevent taps inside card from closing it
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: PlaylistDetailScreen(
                    playlist: _selectedPlaylist!,
                    handler: widget.handler,
                    onClose: _closePlaylistDetail,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  ],
),
),
);
  }

  Widget _buildTabChip({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final key = _tabKeys.putIfAbsent(index, () => GlobalKey());
    final isSelected = _tabController.index == index;

    return KeyedSubtree(
      key: key,
      child: InkWell(
        onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isSelected ? CyberpunkTheme.violetCyanGradient : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.03),
          border: isSelected
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.8,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CyberpunkTheme.neonCyan.withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.black
                  : Colors.white.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.0,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.black
                    : Colors.white.withValues(alpha: 0.75),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  List<TrackEntity> _getFilteredTracks(List<TrackEntity> source) {
    var list = source.where((t) {
      if (_onlyOffline && !t.isDownloaded && (t.localPath == null || t.localPath!.isEmpty)) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
    }).toList();

    switch (_sortMode) {
      case _LibrarySortMode.titleAsc:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _LibrarySortMode.artistAsc:
        list.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _LibrarySortMode.dateDesc:
        break;
    }
    return list;
  }

  Future<void> _shuffleFilteredFavorites(List<TrackEntity> source) async {
    final filtered = _getFilteredTracks(source);
    if (filtered.isEmpty) return;
    WaveService.instance.stopWave();
    final mediaItems = filtered.map((t) => t.toMediaItem()).toList();
    // Вызываем честную перетасовку из handler
    await widget.handler.playShuffledQueue(mediaItems);
  }

  Widget _buildFavoritesTab() {
    final filtered = _getFilteredTracks(_favoriteTracks);

    return Column(
      children: [
        _buildFavoritesToolbar(filtered.length, _favoriteTracks.length),
        Expanded(
          child: filtered.isEmpty
              ? (_searchQuery.trim().isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 40,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'НИЧЕГО НЕ НАЙДЕНО ПО ЗАПРОСУ',
                              style: TextStyle(
                                color: CyberpunkTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'По запросу «$_searchQuery» треков не найдено',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CyberpunkTheme.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _onlyOffline = false;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('СБРОСИТЬ ФИЛЬТРЫ'),
                              style: TextButton.styleFrom(
                                foregroundColor: CyberpunkTheme.neonCyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const _LibraryEmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'ИЗБРАННОЕ ПУСТО',
                      subtitle:
                          'Нажимайте на сердечко в поиске, мини-плеере или '
                          'полноэкранном плеере. Треку не нужно быть скачанным.',
                    ))
              : _buildTrackList(
                  tracks: filtered,
                  emptyIcon: Icons.favorite_border_rounded,
                  emptyTitle: 'ИЗБРАННОЕ ПУСТО',
                  emptySubtitle: '',
                ),
        ),
      ],
    );
  }

  Widget _buildFavoritesToolbar(int filteredCount, int totalCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              // Поле быстрого поиска в стиле GlassCard
              Expanded(
                child: GlassCard(
                  borderRadius: 14,
                  blur: 14,
                  backgroundOpacity: _searchFocusNode.hasFocus ? 0.08 : 0.04,
                  borderGradient: _searchFocusNode.hasFocus
                      ? LinearGradient(
                          colors: [
                            CyberpunkTheme.neonCyan.withValues(alpha: 0.8),
                            CyberpunkTheme.electricViolet.withValues(alpha: 0.5),
                          ],
                        )
                      : CyberpunkTheme.glassBorderGradientSoft,
                  glowColor: _searchFocusNode.hasFocus
                      ? CyberpunkTheme.neonCyan
                      : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      // СТРОГАЯ ИЗОЛЯЦИЯ: хоткеи плеера не перехватываются при вводе текста
                      return KeyEventResult.skipRemainingHandlers;
                    },
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      style: TextStyle(
                        color: CyberpunkTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        icon: Icon(
                          Icons.search_rounded,
                          color: _searchFocusNode.hasFocus
                              ? CyberpunkTheme.neonCyan
                              : Colors.white.withValues(alpha: 0.4),
                          size: 18,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 11),
                        hintText: 'Поиск по трекам и артистам...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                color: Colors.white.withValues(alpha: 0.6),
                                splashRadius: 14,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Неоновая кнопка [ 🔀 ПЕРЕМЕШАТЬ ]
              ElevatedButton.icon(
                onPressed: filteredCount > 0
                    ? () => _shuffleFilteredFavorites(_favoriteTracks)
                    : null,
                icon: const Icon(
                  Icons.shuffle_rounded,
                  size: 16,
                  color: Colors.black,
                ),
                label: const Text(
                  'ПЕРЕМЕШАТЬ',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberpunkTheme.neonGreen,
                  elevation: 6,
                  shadowColor: CyberpunkTheme.neonGreen.withValues(alpha: 0.4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Неоновая кнопка [ 💾 СКАЧАТЬ ВСЕ ]
              ElevatedButton.icon(
                onPressed: _favoriteTracks.isNotEmpty
                    ? () => _openBatchDownloadDialog(context, _favoriteTracks)
                    : null,
                icon: const Icon(
                  Icons.download_for_offline_rounded,
                  size: 16,
                  color: Colors.black,
                ),
                label: const Text(
                  'СКАЧАТЬ ВСЕ',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberpunkTheme.neonCyan,
                  elevation: 6,
                  shadowColor: CyberpunkTheme.neonCyan.withValues(alpha: 0.4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Строка: "💾 Только офлайн", сортировка, счетчик "Показано: X из Y"
          Row(
            children: [
              // Чип-фильтр "💾 Только офлайн"
              InkWell(
                onTap: () {
                  setState(() {
                    _onlyOffline = !_onlyOffline;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _onlyOffline
                        ? CyberpunkTheme.neonGreen.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _onlyOffline
                          ? CyberpunkTheme.neonGreen.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.08),
                      width: _onlyOffline ? 1.0 : 0.6,
                    ),
                    boxShadow: _onlyOffline
                        ? [
                            BoxShadow(
                              color: CyberpunkTheme.neonGreen
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _onlyOffline
                            ? Icons.offline_pin_rounded
                            : Icons.cloud_queue_rounded,
                        size: 13,
                        color: _onlyOffline
                            ? CyberpunkTheme.neonGreen
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '💾 Только офлайн',
                        style: TextStyle(
                          color: _onlyOffline
                              ? CyberpunkTheme.neonGreen
                              : Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: _onlyOffline
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Сортировка: "Сначала новые" / "По названию (А–Я)" / "По артисту"
              PopupMenuButton<_LibrarySortMode>(
                tooltip: 'Сортировка избранного',
                splashRadius: 16,
                color: CyberpunkTheme.cardColor,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.8,
                  ),
                ),
                onSelected: (mode) {
                  setState(() {
                    _sortMode = mode;
                  });
                },
                itemBuilder: (context) => _LibrarySortMode.values.map((mode) {
                  final isSelected = _sortMode == mode;
                  return PopupMenuItem<_LibrarySortMode>(
                    value: mode,
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 15,
                          color: isSelected
                              ? CyberpunkTheme.neonCyan
                              : Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: isSelected
                                ? CyberpunkTheme.neonCyan
                                : CyberpunkTheme.textSecondary,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 13,
                        color: CyberpunkTheme.neonCyan,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _sortMode.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Текст: "Показано: X из Y"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.025),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Показано: $filteredCount из $totalCount',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList({
    required List<TrackEntity> tracks,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (tracks.isEmpty) {
      return _LibraryEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    return StreamBuilder<PlaybackState>(
      stream: widget.handler.playbackState,
      builder: (context, playbackSnapshot) {
        final playing = playbackSnapshot.data?.playing ?? false;

        return StreamBuilder<MediaItem?>(
          stream: widget.handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final currentMedia = mediaSnapshot.data;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return _buildTrackTile(
                  track: track,
                  index: index,
                  tracks: tracks,
                  currentMedia: currentMedia,
                  playing: playing,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTrackTile({
    required TrackEntity track,
    required int index,
    required List<TrackEntity> tracks,
    required MediaItem? currentMedia,
    required bool playing,
  }) {
    final isCurrent = _isCurrentTrack(currentMedia, track);
    final isLocal = _hasLocalFile(track);
    final statusLabel =
        isLocal ? 'LOCAL' : (track.isDownloaded ? 'MISSING' : 'STREAM');
    final statusColor = isLocal
        ? CyberpunkTheme.neonGreen
        : track.isDownloaded
            ? CyberpunkTheme.neonAmber
            : CyberpunkTheme.neonCyan;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 16,
        blur: 12,
        backgroundOpacity: isCurrent ? 0.075 : 0.04,
        borderGradient: isCurrent
            ? LinearGradient(
                colors: [
                  CyberpunkTheme.neonCyan.withValues(alpha: 0.62),
                  CyberpunkTheme.electricViolet.withValues(alpha: 0.38),
                ],
              )
            : CyberpunkTheme.glassBorderGradientSoft,
        glowColor: isCurrent ? CyberpunkTheme.neonCyan : null,
        onTap: () => _playTrackAt(tracks, index),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            _LibraryCover(
              coverUrl: track.coverUrl,
              isCurrent: isCurrent,
              isPlaying: playing,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? CyberpunkTheme.neonCyan
                          : CyberpunkTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.05,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.46),
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MetaChip(
                        label: statusLabel,
                        color: statusColor,
                        leadingIcon: isLocal
                            ? Icons.offline_pin_rounded
                            : track.isDownloaded
                                ? Icons.error_outline_rounded
                                : Icons.cloud_queue_rounded,
                      ),
                      _MetaChip(
                        label: track.sourceName.toUpperCase(),
                        color: CyberpunkTheme.textMuted,
                      ),
                      Text(
                        _formatDuration(track.duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _LibraryActionButton(
              icon: track.isFavorite ? Icons.favorite : Icons.favorite_border,
              tooltip: track.isFavorite
                  ? 'Убрать из избранного'
                  : 'Добавить в избранное',
              color: track.isFavorite
                  ? const Color(0xFFFF2A6D)
                  : ThemeController.colors.textSecondary.withValues(alpha: 0.5),
              backgroundColor: track.isFavorite
                  ? const Color(0xFFFF2A6D).withValues(alpha: 0.12)
                  : Colors.transparent,
              isBusy: _favoriteBusy.contains(track.id),
              onPressed: () => _toggleFavorite(track),
            ),
            _buildMenu(track, isLocal, tracks, index),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: CyberVisualizer(
                  isPlaying: playing,
                  barCount: 4,
                  maxHeight: 16,
                  color: CyberpunkTheme.neonCyan,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(
    TrackEntity track,
    bool isLocal,
    List<TrackEntity> tracks,
    int index,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      splashRadius: 18,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 19,
        color: Colors.white.withValues(alpha: 0.36),
      ),
      color: CyberpunkTheme.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      onSelected: (value) {
        switch (value) {
          case 'play':
            _playTrackAt(tracks, index);
            break;
          case 'add_to_playlist':
            AddToPlaylistModal.show(context, track);
            break;
          case 'explorer':
            _openInExplorer(track.localPath);
            break;
          case 'remove_download':
            _removeDownload(track);
            break;
          case 'unfavorite':
            _toggleFavorite(track);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'play',
          child: _PopupRow(
            icon: Icons.play_arrow_rounded,
            color: CyberpunkTheme.neonCyan,
            label: 'Воспроизвести',
          ),
        ),
        PopupMenuItem<String>(
          value: 'add_to_playlist',
          child: _PopupRow(
            icon: Icons.playlist_add_rounded,
            color: CyberpunkTheme.neonCyan,
            label: 'Добавить в плейлист…',
          ),
        ),
        if (isLocal && Platform.isWindows)
          PopupMenuItem<String>(
            value: 'explorer',
            child: _PopupRow(
              icon: Icons.folder_open_rounded,
              color: CyberpunkTheme.neonAmber,
              label: 'Показать в проводнике',
            ),
          ),
        if (track.isDownloaded)
          PopupMenuItem<String>(
            value: 'remove_download',
            child: _PopupRow(
              icon: Icons.delete_outline_rounded,
              color: CyberpunkTheme.neonPink,
              label: 'Удалить с устройства',
            ),
          ),
        if (track.isFavorite)
          PopupMenuItem<String>(
            value: 'unfavorite',
            child: _PopupRow(
              icon: Icons.heart_broken_rounded,
              color: CyberpunkTheme.electricViolet,
              label: 'Убрать из избранного',
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // History Tab Builder
  // ---------------------------------------------------------------------------
  Widget _buildHistoryList() {
    if (_historyTracks.isEmpty) {
      return const _LibraryEmptyState(
        icon: Icons.history_rounded,
        title: 'ИСТОРИЯ ПУСТА',
        subtitle:
            'Слушайте треки непрерывно более 25 секунд, и они автоматически появятся здесь.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _historyTracks.length,
      itemBuilder: (context, index) {
        final item = _historyTracks[index];
        final title = item['title'] as String? ?? 'Unknown Title';
        final artist = item['artist'] as String? ?? 'Unknown Artist';
        final artworkUrl = item['artwork_url'] as String?;
        final playedAt = item['played_at'] as int? ?? 0;
        final timeText = _formatRelativeTime(playedAt);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            borderRadius: 14,
            blur: 12,
            backgroundOpacity: 0.035,
            borderGradient: CyberpunkTheme.glassBorderGradientSoft,
            onTap: () => _playHistoryItem(item),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: CyberpunkTheme.surfaceColor,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: artworkUrl != null && artworkUrl.isNotEmpty
                        ? Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.music_note_rounded,
                              color: CyberpunkTheme.neonCyan,
                              size: 22,
                            ),
                          )
                        : Icon(
                            Icons.music_note_rounded,
                            color: CyberpunkTheme.neonCyan,
                            size: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CyberpunkTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              CyberpunkTheme.neonCyan.withValues(alpha: 0.72),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: CyberpunkTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeText,
                        style: TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: 'Действия',
                  splashRadius: 18,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.36),
                  ),
                  color: CyberpunkTheme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  onSelected: (value) {
                    final durationSec = item['duration_seconds'] as int? ?? 0;
                    final historyTrack = TrackEntity(
                      id: 'hist_${item['id']}_${title.hashCode.abs()}',
                      title: title,
                      artist: artist,
                      duration: Duration(seconds: durationSec),
                      streamUrl: artworkUrl ?? '',
                      coverUrl: artworkUrl,
                      sourceName: 'history',
                      createdAt: DateTime.fromMillisecondsSinceEpoch(playedAt),
                    );
                    if (value == 'play') {
                      _playHistoryItem(item);
                    } else if (value == 'add_to_playlist') {
                      AddToPlaylistModal.show(context, historyTrack);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'play',
                      child: _PopupRow(
                        icon: Icons.play_arrow_rounded,
                        color: CyberpunkTheme.neonCyan,
                        label: 'Воспроизвести',
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'add_to_playlist',
                      child: _PopupRow(
                        icon: Icons.playlist_add_rounded,
                        color: CyberpunkTheme.neonCyan,
                        label: 'Добавить в плейлист…',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Playlists Tab Implementation
  // ---------------------------------------------------------------------------

  Future<void> _openCreatePlaylistDialog() async {
    final created = await CreatePlaylistDialog.show(context);
    if (created != null && mounted) {
      await _loadTracks(showSpinner: false);
    }
  }

  void _openPlaylistDetail(PlaylistEntity pl) {
    setState(() {
      _selectedPlaylist = pl;
    });
  }

  void _closePlaylistDetail() {
    if (_selectedPlaylist != null) {
      setState(() {
        _selectedPlaylist = null;
      });
      _loadTracks(showSpinner: false);
    }
  }

  Future<void> _playPlaylistAll(PlaylistEntity pl) async {
    final tracks = await _dbService.getPlaylistTracks(pl.id);
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('В плейлисте нет треков для воспроизведения'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final items = tracks.map((t) => t.toMediaItem()).toList();
    await widget.handler.setQueueAndPlay(
      items,
      0,
      mode: AudioSourceMode.library,
    );
  }

  Widget _buildPlaylistsTab() {
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: CyberpunkTheme.neonCyan.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: CyberpunkTheme.neonCyan.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.queue_music_rounded,
                size: 38,
                color: CyberpunkTheme.neonCyan,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'НЕТ СОЗДАННЫХ ПЛЕЙЛИСТОВ',
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                'Создавайте персональные подборки треков, группируйте любимую музыку и настраивайте порядок воспроизведения.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyberpunkTheme.textSecondary.withValues(alpha: 0.8),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openCreatePlaylistDialog,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Создать первый плейлист'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CyberpunkTheme.neonCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.74,
          ),
          itemCount: _playlists.length,
          itemBuilder: (context, index) {
            final pl = _playlists[index];
            return _buildPlaylistCard(pl);
          },
        );
      },
    );
  }

  Color _parsePlColor(String? hex) {
    if (hex == null || hex.isEmpty) return CyberpunkTheme.neonCyan;
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return CyberpunkTheme.neonCyan;
    }
  }

  String _formatPlDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} ч ${d.inMinutes % 60} мин';
    }
    return '${d.inMinutes} мин';
  }

  Widget _buildPlaylistCard(PlaylistEntity pl) {
    final accentColor = _parsePlColor(pl.color);

    return GlassCard(
      borderRadius: 18,
      blur: 16,
      backgroundOpacity: 0.05,
      borderGradient: CyberpunkTheme.glassBorderGradientSoft,
      glowColor: accentColor,
      padding: const EdgeInsets.all(12),
      onTap: () => _openPlaylistDetail(pl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mosaic Cover with quick play button overlay
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCardMosaic(pl, accentColor),
                // Quick start button: Слушать всё
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _playPlaylistAll(pl),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.6),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            pl.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          // Meta info
          Row(
            children: [
              Text(
                '${pl.trackCount} треков',
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (pl.totalDuration > Duration.zero) ...[
                Text(
                  ' · ',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  _formatPlDuration(pl.totalDuration),
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardMosaic(PlaylistEntity pl, Color accentColor) {
    final covers = pl.coverUrls;

    if (covers.length >= 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildCoverTile(covers[0])),
                  Expanded(child: _buildCoverTile(covers[1])),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildCoverTile(covers[2])),
                  Expanded(child: _buildCoverTile(covers[3])),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (covers.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _buildCoverTile(covers.first),
      );
    }

    // Default cyberpunk empty playlist icon
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: accentColor.withValues(alpha: 0.8),
          size: 42,
        ),
      ),
    );
  }

  Widget _buildCoverTile(String url) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholderTile(),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholderTile(),
      );
    }
    return _coverPlaceholderTile();
  }

  Widget _coverPlaceholderTile() {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.music_note_rounded, size: 20, color: Colors.white24),
    );
  }

  // ---------------------------------------------------------------------------
  Future<void> _playArtistTopTrack({
    required String title,
    required String artist,
    String? artworkUrl,
    int durationSeconds = 0,
  }) async {
    WaveService.instance.stopWave();
    // 1. Поиск среди загруженных треков
    for (final t in _downloadedTracks) {
      if (t.title.trim().toLowerCase() == title.trim().toLowerCase() &&
          t.artist.trim().toLowerCase() == artist.trim().toLowerCase()) {
        await widget.handler.playMediaItem(t.toMediaItem());
        return;
      }
    }
    // 2. Поиск среди избранных треков
    for (final t in _favoriteTracks) {
      if (t.title.trim().toLowerCase() == title.trim().toLowerCase() &&
          t.artist.trim().toLowerCase() == artist.trim().toLowerCase()) {
        await widget.handler.playMediaItem(t.toMediaItem());
        return;
      }
    }
    // 3. Воспроизведение через MediaItem
    final mediaItem = MediaItem(
      id: 'top_artist_${artist.hashCode}_${title.hashCode}',
      title: title,
      artist: artist,
      duration: Duration(seconds: durationSeconds),
      artUri: artworkUrl != null && artworkUrl.isNotEmpty
          ? Uri.tryParse(artworkUrl)
          : null,
    );
    await widget.handler.playMediaItem(mediaItem);
  }

  // ---------------------------------------------------------------------------
  // Top Artists Tab Builder (Центрированная лента с топ-3 треками)
  // ---------------------------------------------------------------------------
  Widget _buildTopArtistsList() {
    if (_topArtists.isEmpty) {
      return const _LibraryEmptyState(
        icon: Icons.stars_rounded,
        title: 'НЕТ ДАННЫХ ОБ АРТИСТАХ',
        subtitle:
            'Слушайте любимую музыку, и здесь сформируется топ ваших исполнителей.',
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _topArtists.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final artistData = _topArtists[index];
            final name = artistData['artist'] as String? ?? 'Unknown Artist';
            final totalPlays = artistData['total_plays'] as int? ?? 0;
            final artworkUrl = artistData['artwork_url'] as String?;
            final topTracks = (artistData['top_tracks'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                const [];

            final isFirst = index == 0;
            final isSecond = index == 1;
            final isThird = index == 2;
            final rankColor = isFirst
                ? const Color(0xFFFFD700) // #1 Золотой
                : (isSecond
                    ? CyberpunkTheme.neonCyan // #2 Циан
                    : (isThird
                        ? CyberpunkTheme.electricViolet // #3 Фиолетовый
                        : CyberpunkTheme.textMuted));

            return GlassCard(
              borderRadius: 20,
              blur: 16,
              backgroundOpacity: isFirst ? 0.09 : (isSecond ? 0.07 : 0.04),
              borderGradient: isFirst
                  ? LinearGradient(
                      colors: [
                        const Color(0xFFFFD700).withValues(alpha: 0.7),
                        CyberpunkTheme.neonPink.withValues(alpha: 0.45),
                      ],
                    )
                  : (isSecond
                      ? LinearGradient(
                          colors: [
                            CyberpunkTheme.neonCyan.withValues(alpha: 0.6),
                            CyberpunkTheme.neonGreen.withValues(alpha: 0.35),
                          ],
                        )
                      : (isThird
                          ? LinearGradient(
                              colors: [
                                CyberpunkTheme.electricViolet
                                    .withValues(alpha: 0.6),
                                CyberpunkTheme.neonPink.withValues(alpha: 0.35),
                              ],
                            )
                          : CyberpunkTheme.glassBorderGradientSoft)),
              glowColor: isFirst
                  ? const Color(0xFFFFD700)
                  : (isSecond
                      ? CyberpunkTheme.neonCyan
                      : (isThird ? CyberpunkTheme.electricViolet : null)),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Шапка: Ранг, круглый аватар 48x48 с неоновым контуром, имя исполнителя (16px, bold), бейдж "🔥 N прослушиваний"
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rankColor.withValues(alpha: 0.16),
                          border: Border.all(
                            color: rankColor.withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          boxShadow: [
                            if (isFirst || isSecond || isThird)
                              BoxShadow(
                                color: rankColor.withValues(alpha: 0.3),
                                blurRadius: 8,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                              color: rankColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CyberpunkTheme.surfaceColor,
                          border: Border.all(
                            color: rankColor.withValues(alpha: 0.65),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: rankColor.withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: artworkUrl != null && artworkUrl.isNotEmpty
                              ? Image.network(
                                  artworkUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    color: rankColor,
                                    size: 26,
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  color: rankColor,
                                  size: 26,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: rankColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: rankColor.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '🔥 $totalPlays ${_pluralizePlays(totalPlays)}',
                          style: TextStyle(
                            color: rankColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Разделитель
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      color: Colors.white.withValues(alpha: 0.08),
                      height: 1,
                      thickness: 0.8,
                    ),
                  ),

                  // Внутри: компактный список топ-3 треков
                  if (topTracks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Нет данных о треках',
                        style: TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: List.generate(topTracks.length, (trackIdx) {
                        final trackItem = topTracks[trackIdx];
                        final trackTitle =
                            trackItem['title'] as String? ?? 'Unknown Title';
                        final trackPlays =
                            trackItem['track_plays'] as int? ?? 0;
                        final trackArtwork =
                            trackItem['artwork_url'] as String?;
                        final trackDuration =
                            trackItem['duration_seconds'] as int? ?? 0;

                        return Container(
                          margin: EdgeInsets.only(
                              bottom: trackIdx < topTracks.length - 1 ? 6 : 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.025),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Порядковый номер (1., 2., 3.)
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${trackIdx + 1}.',
                                  style: TextStyle(
                                    color: rankColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Название песни (с TextOverflow.ellipsis)
                              Expanded(
                                child: Text(
                                  trackTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: CyberpunkTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Неоновый бейдж: "N прослушиваний"
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: CyberpunkTheme.neonCyan
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: CyberpunkTheme.neonCyan
                                        .withValues(alpha: 0.35),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  '$trackPlays ${_pluralizePlays(trackPlays)}',
                                  style: TextStyle(
                                    color: CyberpunkTheme.neonCyan,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Кнопка Play (быстрый запуск трека)
                              Tooltip(
                                message: 'Воспроизвести трек',
                                child: InkWell(
                                  onTap: () => _playArtistTopTrack(
                                    title: trackTitle,
                                    artist: name,
                                    artworkUrl: trackArtwork,
                                    durationSeconds: trackDuration,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: CyberpunkTheme.neonCyan
                                          .withValues(alpha: 0.15),
                                      border: Border.all(
                                        color: CyberpunkTheme.neonCyan
                                            .withValues(alpha: 0.5),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      color: CyberpunkTheme.neonCyan,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatRelativeTime(int timestampMs) {
    if (timestampMs <= 0) return '';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(date);

    if (diff.inSeconds < 60) {
      return 'Только что';
    } else if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      final ending = (m % 10 == 1 && m % 100 != 11)
          ? 'минуту'
          : ([2, 3, 4].contains(m % 10) && ![12, 13, 14].contains(m % 100))
              ? 'минуты'
              : 'минут';
      return '$m $ending назад';
    } else if (diff.inHours < 24 && now.day == date.day) {
      final h = diff.inHours;
      final ending = (h % 10 == 1 && h % 100 != 11)
          ? 'час'
          : ([2, 3, 4].contains(h % 10) && ![12, 13, 14].contains(h % 100))
              ? 'часа'
              : 'часов';
      return '$h $ending назад';
    } else if (diff.inDays <= 1 || (diff.inDays <= 2 && now.day != date.day)) {
      return 'Вчера в ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} дн. назад';
    } else {
      const months = [
        'янв',
        'фев',
        'мар',
        'апр',
        'май',
        'июн',
        'июл',
        'авг',
        'сен',
        'окт',
        'ноя',
        'дек'
      ];
      return '${date.day} ${months[date.month - 1]}';
    }
  }

  String _pluralizePlays(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) {
      return 'прослушивание';
    } else if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'прослушивания';
    } else {
      return 'прослушиваний';
    }
  }

  Future<void> _playHistoryItem(Map<String, dynamic> item) async {
    WaveService.instance.stopWave();
    final title = item['title'] as String? ?? 'Unknown Title';
    final artist = item['artist'] as String? ?? 'Unknown Artist';
    final artworkUrl = item['artwork_url'] as String?;
    final durationSeconds = item['duration_seconds'] as int? ?? 0;

    TrackEntity? match;
    for (final t in _downloadedTracks) {
      if (t.title == title && t.artist == artist) {
        match = t;
        break;
      }
    }
    if (match == null) {
      for (final t in _favoriteTracks) {
        if (t.title == title && t.artist == artist) {
          match = t;
          break;
        }
      }
    }

    if (match != null) {
      await widget.handler.playMediaItem(match.toMediaItem());
      return;
    }

    final mediaItem = MediaItem(
      id: 'history_${item['id']}',
      title: title,
      artist: artist,
      duration: Duration(seconds: durationSeconds),
      artUri: artworkUrl != null && artworkUrl.isNotEmpty
          ? Uri.tryParse(artworkUrl)
          : null,
    );
    await widget.handler.playMediaItem(mediaItem);
  }
}

// -----------------------------------------------------------------------------
// Private widgets
// -----------------------------------------------------------------------------
class _LibraryCover extends StatefulWidget {
  final String? coverUrl;
  final bool isCurrent;
  final bool isPlaying;

  const _LibraryCover({
    required this.coverUrl,
    required this.isCurrent,
    this.isPlaying = false,
  });

  @override
  State<_LibraryCover> createState() => _LibraryCoverState();
}

class _LibraryCoverState extends State<_LibraryCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = ThemeController.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isCurrent
                ? colors.neonPrimary.withValues(alpha: 0.6)
                : (_isHovered
                    ? colors.neonPrimary.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.07)),
            width: widget.isCurrent || _isHovered ? 1.0 : 0.5,
          ),
          boxShadow: [
            if (_isHovered || widget.isCurrent)
              BoxShadow(
                color: colors.neonPrimary.withValues(alpha: 0.2),
                blurRadius: 16,
                spreadRadius: 1,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
                Image.network(
                  widget.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _LibraryCoverFallback(),
                )
              else
                const _LibraryCoverFallback(),
              if (widget.isCurrent)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: CyberVisualizer(
                      isPlaying: widget.isPlaying,
                      barCount: 4,
                      maxHeight: 18,
                      color: colors.neonPrimary,
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

class _LibraryCoverFallback extends StatelessWidget {
  const _LibraryCoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeController.colors.bgSurface,
            ThemeController.colors.cardGlass
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: CyberpunkTheme.neonCyan,
          size: 22,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? leadingIcon;

  const _MetaChip({
    required this.label,
    required this.color,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 9, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color backgroundColor;
  final bool isBusy;
  final VoidCallback onPressed;

  const _LibraryActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.backgroundColor = Colors.transparent,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 36,
        child: isBusy
            ? Center(
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    color: CyberpunkTheme.electricViolet,
                  ),
                ),
              )
            : IconButton(
                onPressed: onPressed,
                icon: Icon(icon, size: 19),
                color: color,
                style: IconButton.styleFrom(
                  backgroundColor: backgroundColor,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                splashRadius: 17,
                visualDensity: VisualDensity.compact,
              ),
      ),
    );
  }
}

class _PopupRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _PopupRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: CyberpunkTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LibraryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                  width: 0.5,
                ),
              ),
              child: Icon(
                icon,
                size: 31,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
