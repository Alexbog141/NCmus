import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../scraper/models/scraped_track.dart';
import '../../scraper/providers/hitmo_provider.dart';
import '../../scraper/providers/muzofond_provider.dart';
import '../../scraper/services/mirror_resolver.dart';
import '../../search/services/fuzzy_search_service.dart';
import '../../storage/models/track_entity.dart';
import '../../storage/services/storage_manager.dart';
import '../../wave/services/nc_wave_service.dart';
import '../widgets/add_to_playlist_modal.dart';

/// Search across web mirrors with instant queue playback, fuzzy spell
/// correction and universal favourites.
class SearchScreen extends StatefulWidget {
  final NCPlayerHandler handler;
  final NCWaveService? waveService;

  const SearchScreen({
    super.key,
    required this.handler,
    this.waveService,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final MirrorResolver _mirrorResolver;
  late final HitmoProvider _hitmoProvider;
  late final MuzofondProvider _muzofondProvider;
  late final ScraperEngine _scraperEngine;
  late final DatabaseService _databaseService;
  late final StorageManager _storageManager;
  late final FuzzySearchService _fuzzySearchService;
  late final NCWaveService _waveService;

  StreamSubscription<void>? _librarySubscription;

  List<ScrapedTrack> _searchResults = <ScrapedTrack>[];
  final Set<String> _downloadingTrackIds = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  final Map<String, String> _downloadedLocalPaths = <String, String>{};
  final Set<String> _favoriteTrackIds = <String>{};
  final Set<String> _favoritePending = <String>{};
  final Map<String, TrackEntity> _dbTrackCache = <String, TrackEntity>{};

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isSearchFocused = false;
  bool _isPreparingQueue = false;
  String? _errorMessage;
  int _searchRequestId = 0;
  int _dbRefreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _databaseService = DatabaseService.instance;
    _storageManager = StorageManager(dbService: _databaseService);
    _mirrorResolver = MirrorResolver();
    _hitmoProvider = HitmoProvider(mirrorResolver: _mirrorResolver);
    _muzofondProvider = MuzofondProvider(mirrorResolver: _mirrorResolver);
    _scraperEngine = ScraperEngine(
      providers: [_hitmoProvider, _muzofondProvider],
    );
    _fuzzySearchService = FuzzySearchService(
      scraperEngine: _scraperEngine,
      dbService: _databaseService,
    );
    _waveService = widget.waveService ??
        NCWaveService.instance ??
        NCWaveService(
          handler: widget.handler,
          scraperEngine: _scraperEngine,
          dbService: _databaseService,
        );
    widget.handler.waveService = _waveService;
    _waveService.addListener(_onWaveChanged);

    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isSearchFocused = _focusNode.hasFocus;
      });
    });

    _librarySubscription =
        _databaseService.libraryChanges.listen((_) => _refreshDatabaseState());
    _loadExistingDownloads();
  }

  void _onWaveChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _waveService.removeListener(_onWaveChanged);
    _librarySubscription?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _fuzzySearchService.dispose();
    _hitmoProvider.dispose();
    _muzofondProvider.dispose();
    _storageManager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------
  Future<void> _loadExistingDownloads() async {
    try {
      final downloaded = await _databaseService.getAllDownloadedTracks();
      if (!mounted) return;
      setState(() {
        for (final track in downloaded) {
          final localPath = track.localPath;
          if (localPath != null && File(localPath).existsSync()) {
            _downloadedLocalPaths[track.id] = localPath;
          }
        }
      });
    } catch (_) {
      // The library is optional for a search session.
    }
  }

  Future<void> _refreshDatabaseState() async {
    if (_searchResults.isEmpty) return;

    final generation = ++_dbRefreshGeneration;
    final snapshot = List<ScrapedTrack>.of(_searchResults);
    final favourites = <String>{};
    final cache = <String, TrackEntity>{};

    for (final track in snapshot) {
      try {
        final dbTrack = await _databaseService.getTrack(track.id);
        if (dbTrack == null) continue;
        cache[track.id] = dbTrack;
        if (dbTrack.isFavorite) {
          favourites.add(track.id);
        }
      } catch (_) {
        // Ignore individual lookup failures.
      }
    }

    if (!mounted || generation != _dbRefreshGeneration) return;
    setState(() {
      _favoriteTrackIds
        ..clear()
        ..addAll(favourites);
      _dbTrackCache
        ..clear()
        ..addAll(cache);
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    final requestId = ++_searchRequestId;
    _dbRefreshGeneration++;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final results = await _fuzzySearchService.robustSearch(query);
      if (!mounted || requestId != _searchRequestId) return;

      final favourites = <String>{};
      final cache = <String, TrackEntity>{};
      final localPaths = <String, String>{};

      for (final track in results) {
        try {
          final dbTrack = await _databaseService.getTrack(track.id);
          if (dbTrack == null) continue;

          cache[track.id] = dbTrack;
          if (dbTrack.isFavorite) {
            favourites.add(track.id);
          }

          final localPath = dbTrack.localPath;
          if (dbTrack.isDownloaded &&
              localPath != null &&
              File(localPath).existsSync()) {
            localPaths[track.id] = localPath;
          }
        } catch (_) {
          // Search results should still render if one DB lookup fails.
        }
      }

      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = results;
        _dbTrackCache
          ..clear()
          ..addAll(cache);
        _favoriteTrackIds
          ..clear()
          ..addAll(favourites);
        _downloadedLocalPaths.addAll(localPaths);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _errorMessage = 'Ошибка поиска: $error';
        _isLoading = false;
      });
    }
  }

  TrackEntity _entityFor(
    ScrapedTrack track, {
    bool isFavorite = false,
    String? localPath,
    bool? isDownloaded,
  }) {
    final hasLocalFile = localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    return TrackEntity(
      id: track.id,
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      streamUrl: track.streamUrl,
      localPath: localPath,
      coverUrl: track.coverUrl,
      sourceName: track.sourceName,
      isDownloaded: isDownloaded ?? hasLocalFile,
      isFavorite: isFavorite,
      createdAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Favourites
  // ---------------------------------------------------------------------------
  Future<void> _toggleFavorite(ScrapedTrack track) async {
    if (_favoritePending.contains(track.id)) return;

    final wasFavorite = _favoriteTrackIds.contains(track.id);
    final nextValue = !wasFavorite;

    setState(() {
      _favoritePending.add(track.id);
      if (nextValue) {
        _favoriteTrackIds.add(track.id);
      } else {
        _favoriteTrackIds.remove(track.id);
      }
    });

    try {
      final localPath = _downloadedLocalPaths[track.id];
      var existing = _dbTrackCache[track.id];

      if (existing == null) {
        // The search session cache can be empty while the row still exists in
        // SQLite. Never replace such a row blindly: that could drop local_path
        // or an already downloaded copy.
        existing = await _databaseService.getTrack(track.id);
        if (existing != null) {
          _dbTrackCache[track.id] = existing;
        }
      }

      if (existing == null) {
        final entity = _entityFor(
          track,
          isFavorite: nextValue,
          localPath: localPath,
          isDownloaded: localPath != null,
        );
        await _databaseService.insertOrUpdateTrack(entity);
        _dbTrackCache[track.id] = entity;
      } else {
        await _databaseService.toggleFavorite(track.id, nextValue);
        _dbTrackCache[track.id] = existing.copyWith(isFavorite: nextValue);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteTrackIds.add(track.id);
        } else {
          _favoriteTrackIds.remove(track.id);
        }
      });
      _showError('Не удалось обновить избранное: $error');
    } finally {
      if (mounted) {
        setState(() {
          _favoritePending.remove(track.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------
  Future<void> _downloadTrack(ScrapedTrack track) async {
    if (_downloadingTrackIds.contains(track.id)) return;

    setState(() {
      _downloadingTrackIds.add(track.id);
      _downloadProgress[track.id] = 0;
    });

    try {
      final localPath = await _storageManager.downloadAndTagTrack(
        track: track,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _downloadProgress[track.id] = progress.clamp(0.0, 1.0);
          });
        },
      );

      if (!mounted) return;

      final cached = _dbTrackCache[track.id];
      final entity = (cached ??
              _entityFor(
                track,
                isFavorite: _favoriteTrackIds.contains(track.id),
              ))
          .copyWith(
        localPath: localPath,
        isDownloaded: true,
      );

      setState(() {
        _downloadingTrackIds.remove(track.id);
        _downloadProgress.remove(track.id);
        _downloadedLocalPaths[track.id] = localPath;
        _dbTrackCache[track.id] = entity;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadingTrackIds.remove(track.id);
        _downloadProgress.remove(track.id);
      });
      _showError('Не удалось скачать трек: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Playback / queue
  // ---------------------------------------------------------------------------
  Future<void> _playFromResults(int index) async {
    if (_isPreparingQueue || _searchResults.isEmpty) return;
    _isPreparingQueue = true;

    try {
      final items = <MediaItem>[];

      for (final track in _searchResults) {
        final localPath = _downloadedLocalPaths[track.id];
        var entity = _dbTrackCache[track.id];

        if (entity == null) {
          entity = _entityFor(
            track,
            isFavorite: _favoriteTrackIds.contains(track.id),
            localPath: localPath,
            isDownloaded: localPath != null,
          );
        } else if (localPath != null && entity.localPath != localPath) {
          entity = entity.copyWith(
            localPath: localPath,
            isDownloaded: true,
          );
        }

        items.add(entity.toMediaItem());
      }

      final safeIndex = index.clamp(0, items.length - 1).toInt();
      await widget.handler.setQueueAndPlay(items, safeIndex);
    } catch (error) {
      if (mounted) {
        _showError('Ошибка воспроизведения: $error');
      }
    } finally {
      _isPreparingQueue = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------
  void _showError(String message) {
    debugPrint(message);
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

  bool _isCurrentTrack(
    MediaItem? current,
    ScrapedTrack track,
    String? localPath,
  ) {
    if (current == null) return false;
    if (current.extras?['originalId'] == track.id) return true;
    if (current.id == track.streamUrl) return true;
    if (localPath != null && current.id == localPath) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: _buildSearchField(),
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildSearchField() {
    return GlassCard(
      borderRadius: 18,
      blur: 18,
      backgroundOpacity: _isSearchFocused ? 0.07 : 0.045,
      borderGradient: _isSearchFocused
          ? LinearGradient(
              colors: [
                CyberpunkTheme.neonCyan.withValues(alpha: 0.7),
                CyberpunkTheme.electricViolet.withValues(alpha: 0.5),
              ],
            )
          : CyberpunkTheme.glassBorderGradientSoft,
      glowColor: _isSearchFocused ? CyberpunkTheme.neonCyan : null,
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: _isSearchFocused
                ? CyberpunkTheme.neonCyan
                : Colors.white.withValues(alpha: 0.36),
            size: 20,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 14,
              ),
              cursorColor: CyberpunkTheme.neonCyan,
              decoration: InputDecoration(
                hintText: 'Найти артиста или трек...',
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              splashRadius: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Очистить',
            ),
          const SizedBox(width: 4),
          _SearchSubmitButton(
            isEnabled: !_isLoading,
            onPressed: _performSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildInitialSearchState() {
    final chips = [
      'Linkin Park',
      'Slipknot',
      'Phonk',
      'Cyberpunk 2077',
      'The Weeknd',
      'Rammstein',
      'Synthwave',
      'Post-Punk',
      'Deftones',
      'Nirvana',
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberpunkTheme.neonCyan.withValues(alpha: 0.08),
                  border: Border.all(
                    color: CyberpunkTheme.neonCyan.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.search_rounded,
                    size: 36,
                    color: CyberpunkTheme.neonCyan,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'ПОИСК МУЗЫКИ',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Введите название трека или имя исполнителя для мгновенного поиска по зеркалам Hitmo и Muzofond',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyberpunkTheme.textSecondary.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'БЫСТРЫЙ ПОИСК',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final tag in chips)
                    ActionChip(
                      label: Text(tag),
                      labelStyle: TextStyle(
                        color: CyberpunkTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      backgroundColor:
                          CyberpunkTheme.surfaceColor.withValues(alpha: 0.5),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onPressed: () {
                        _searchController.text = tag;
                        _performSearch();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.035),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CyberpunkTheme.neonCyan,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ПОИСК ПО ЗЕРКАЛАМ',
              style: TextStyle(
                color: CyberpunkTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.7,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Hitmo & Muzofond',
              style: TextStyle(
                color: CyberpunkTheme.textMuted.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _CenteredState(
        icon: Icons.cloud_off_rounded,
        accent: CyberpunkTheme.neonPink,
        title: 'ПОИСК НЕДОСТУПЕН',
        subtitle: _errorMessage!,
        actionLabel: 'ПОВТОРИТЬ',
        onAction: _performSearch,
      );
    }

    if (!_hasSearched) {
      return _buildInitialSearchState();
    }

    if (_searchResults.isEmpty) {
      return _CenteredState(
        icon: Icons.search_off_rounded,
        accent: CyberpunkTheme.electricViolet,
        title: 'НИЧЕГО НЕ НАЙДЕНО',
        subtitle:
            'По запросу «${_searchController.text.trim()}» результатов нет. '
            'Попробуйте другое написание.',
      );
    }

    return StreamBuilder<PlaybackState>(
      stream: widget.handler.playbackState,
      builder: (context, playbackSnapshot) {
        final playback = playbackSnapshot.data;
        final playing = playback?.playing ?? false;

        return StreamBuilder<MediaItem?>(
          stream: widget.handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final currentMedia = mediaSnapshot.data;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                  child: Row(
                    children: [
                      Text(
                        'РЕЗУЛЬТАТЫ · ${_searchResults.length}',
                        style: TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.queue_music_rounded,
                        size: 13,
                        color: CyberpunkTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ОЧЕРЕДЬ · ${_searchResults.length}',
                        style: TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final track = _searchResults[index];
                      return _buildResultTile(
                        track: track,
                        index: index,
                        currentMedia: currentMedia,
                        playing: playing,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildResultTile({
    required ScrapedTrack track,
    required int index,
    required MediaItem? currentMedia,
    required bool playing,
  }) {
    final localPath = _downloadedLocalPaths[track.id];
    final isDownloaded = localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();
    final isDownloading = _downloadingTrackIds.contains(track.id);
    final progress = _downloadProgress[track.id] ?? 0.0;
    final isFavorite = _favoriteTrackIds.contains(track.id);
    final favoriteBusy = _favoritePending.contains(track.id);
    final isCurrent = _isCurrentTrack(currentMedia, track, localPath);
    final isHitmo = track.sourceName.toLowerCase().contains('hitmo');

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
        onTap: () => _playFromResults(index),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            _ResultCover(
              coverUrl: track.coverUrl,
              isCurrent: isCurrent,
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
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.46),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDuration(track.duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 7),
                      _SourceBadge(
                        sourceName: track.sourceName,
                        isHitmo: isHitmo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TileActionButton(
              icon: isFavorite
                  ? Icons.favorite
                  : Icons.favorite_border,
              tooltip:
                  isFavorite ? 'Убрать из избранного' : 'Добавить в избранное',
              color: isFavorite
                  ? const Color(0xFFFF2A6D)
                  : ThemeController.colors.textSecondary.withValues(alpha: 0.5),
              backgroundColor: isFavorite
                  ? const Color(0xFFFF2A6D).withValues(alpha: 0.15)
                  : Colors.transparent,
              isBusy: favoriteBusy,
              onPressed: () => _toggleFavorite(track),
            ),
            const SizedBox(width: 2),
            if (isDownloading)
              Tooltip(
                message: 'Скачивание ${(progress * 100).round()}%',
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 2,
                      color: CyberpunkTheme.neonCyan,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              )
            else
              _TileActionButton(
                icon: isDownloaded
                    ? Icons.check_circle_rounded
                    : Icons.arrow_circle_down_rounded,
                tooltip:
                    isDownloaded ? 'Скачано — воспроизвести' : 'Скачать трек',
                color: isDownloaded
                    ? CyberpunkTheme.neonGreen
                    : Colors.white.withValues(alpha: 0.42),
                onPressed: isDownloaded
                    ? () => _playFromResults(index)
                    : () => _downloadTrack(track),
              ),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 2),
                child: Icon(
                  playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                  size: 17,
                  color: CyberpunkTheme.neonCyan.withValues(alpha: 0.8),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'Действия',
              splashRadius: 18,
              icon: Icon(
                Icons.more_vert_rounded,
                size: 19,
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
              onSelected: (val) {
                if (val == 'add_to_playlist') {
                  final entity = _dbTrackCache[track.id] ??
                      TrackEntity.fromScrapedTrack(
                        track,
                        localPath: localPath,
                        isDownloaded: isDownloaded,
                        isFavorite: isFavorite,
                      );
                  AddToPlaylistModal.show(context, entity);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'add_to_playlist',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_rounded,
                          size: 18, color: CyberpunkTheme.neonCyan),
                      const SizedBox(width: 8),
                      const Text('Добавить в плейлист…'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Private widgets
// -----------------------------------------------------------------------------
class _SearchSubmitButton extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onPressed;

  const _SearchSubmitButton({
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isEnabled ? 1 : 0.45,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: CyberpunkTheme.cyanVioletGradient,
          boxShadow: [
            BoxShadow(
              color: CyberpunkTheme.neonCyan.withValues(alpha: 0.2),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isEnabled ? onPressed : null,
            child: const Icon(
              Icons.arrow_forward_rounded,
              size: 19,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}


class _ResultCover extends StatelessWidget {
  final String? coverUrl;
  final bool isCurrent;

  const _ResultCover({
    required this.coverUrl,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? CyberpunkTheme.neonCyan.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.07),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl != null && coverUrl!.isNotEmpty)
              Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
              )
            else
              const _CoverPlaceholder(),
            if (isCurrent)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.42),
                child: Center(
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: CyberpunkTheme.neonCyan,
                    size: 21,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ThemeController.colors.bgSurface, ThemeController.colors.cardGlass],
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

class _SourceBadge extends StatelessWidget {
  final String sourceName;
  final bool isHitmo;

  const _SourceBadge({
    required this.sourceName,
    required this.isHitmo,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isHitmo ? CyberpunkTheme.electricViolet : CyberpunkTheme.neonCyan;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 0.5,
        ),
      ),
      child: Text(
        sourceName.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.88),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TileActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color backgroundColor;
  final bool isBusy;
  final VoidCallback onPressed;

  const _TileActionButton({
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
        width: 36,
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

class _CenteredState extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredState({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(
                  color: accent.withValues(alpha: 0.18),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.1),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              GlassCard(
                borderRadius: 14,
                blur: 14,
                backgroundOpacity: 0.05,
                borderGradient: CyberpunkTheme.glassBorderGradient,
                glowColor: CyberpunkTheme.neonCyan,
                onTap: onAction,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: CyberpunkTheme.neonCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



