import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../storage/models/playlist_entity.dart';

/// Cyberpunk-styled modal dialog to create or edit a playlist.
class CreatePlaylistDialog extends StatefulWidget {
  final PlaylistEntity? initialPlaylist;

  const CreatePlaylistDialog({
    super.key,
    this.initialPlaylist,
  });

  static Future<PlaylistEntity?> show(
    BuildContext context, {
    PlaylistEntity? initialPlaylist,
  }) {
    return showDialog<PlaylistEntity?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CreatePlaylistDialog(
        initialPlaylist: initialPlaylist,
      ),
    );
  }

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late String _selectedColorHex;
  bool _isSaving = false;

  static const List<String> _neonPalette = [
    '#00F0FF', // Neon Cyan
    '#B026FF', // Electric Violet
    '#FF007F', // Neon Pink
    '#00FF66', // Neon Green
    '#FFE600', // Cyber Gold
    '#0080FF', // Cyber Blue
  ];

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.initialPlaylist?.title ?? '');
    _descController =
        TextEditingController(text: widget.initialPlaylist?.description ?? '');
    _selectedColorHex = widget.initialPlaylist?.color ?? _neonPalette.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return CyberpunkTheme.neonCyan;
    }
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final db = DatabaseService.instance;
      final desc = _descController.text.trim();

      if (widget.initialPlaylist != null) {
        await db.updatePlaylist(
          widget.initialPlaylist!.id,
          title: title,
          description: desc,
          color: _selectedColorHex,
        );
        final updated = widget.initialPlaylist!.copyWith(
          title: title,
          description: desc,
          color: _selectedColorHex,
        );
        if (mounted) Navigator.of(context).pop(updated);
      } else {
        final created = await db.createPlaylist(
          title,
          description: desc.isNotEmpty ? desc : null,
          color: _selectedColorHex,
        );
        if (mounted) Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialPlaylist != null;
    final activeAccentColor = _parseColor(_selectedColorHex);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E17).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: activeAccentColor.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: activeAccentColor.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: activeAccentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: activeAccentColor.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_note_rounded
                            : Icons.playlist_add_rounded,
                        color: activeAccentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'РЕДАКТИРОВАТЬ ПЛЕЙЛИСТ'
                                : 'СОЗДАТЬ ПЛЕЙЛИСТ',
                            style: TextStyle(
                              color: CyberpunkTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEditing
                                ? 'Измените параметры коллекции'
                                : 'Новая неоновая подборка треков',
                            style: TextStyle(
                              color: CyberpunkTheme.textSecondary
                                  .withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Colors.white.withValues(alpha: 0.5),
                      splashRadius: 18,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Name Input
                Text(
                  'НАЗВАНИЕ',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Например, Ночной Дрифт или Synthwave Core',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: activeAccentColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _handleSave(),
                ),
                const SizedBox(height: 16),

                // Description Input
                Text(
                  'ОПИСАНИЕ (ОПЦИОНАЛЬНО)',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Краткая атмосфера или описание подборки...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: activeAccentColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Accent Neon Color
                Text(
                  'НЕОНОВЫЙ АКЦЕНТ',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _neonPalette.map((hex) {
                    final color = _parseColor(hex);
                    final isSelected = _selectedColorHex == hex;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedColorHex = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isSelected ? 0.3 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? color
                                : color.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 0.8,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: isSelected
                              ? Icon(Icons.check_rounded,
                                  color: color, size: 20)
                              : Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 26),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('ОТМЕНА'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeAccentColor,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shadowColor: activeAccentColor.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 13,
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              isEditing ? 'СОХРАНИТЬ' : 'СОЗДАТЬ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                fontSize: 13,
                              ),
                            ),
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
