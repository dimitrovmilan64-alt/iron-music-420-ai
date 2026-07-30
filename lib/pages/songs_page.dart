import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/song_project.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class SongsPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback onOpenStudio;

  const SongsPage({
    super.key,
    required this.store,
    required this.onOpenStudio,
  });

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SongProject> _filteredSongs(List<SongProject> songs) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return songs;
    return songs.where((song) {
      final haystack = [
        song.title,
        song.theme,
        song.style,
        song.mood,
        song.lyrics,
        song.musicPrompt,
        song.excludePrompt,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}  ${two(date.hour)}:${two(date.minute)}';
  }

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-Я_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'iron_music_song' : cleaned;
  }

  Future<void> _copySong(SongProject song) async {
    await Clipboard.setData(ClipboardData(text: song.exportText));
    if (mounted) _showMessage('Песента е копирана.');
  }

  Future<void> _copySunoPackage(SongProject song) async {
    await Clipboard.setData(ClipboardData(text: song.sunoPackageText));
    if (mounted) _showMessage('Suno пакетът е копиран.');
  }

  Future<void> _exportSong(SongProject song) async {
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            utf8.encode(song.exportText),
            mimeType: 'text/plain',
          ),
        ],
        text: song.title,
        subject: 'Iron Music 420 AI — ${song.title}',
        fileNameOverrides: ['${_safeFileName(song.title)}.txt'],
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Експортът не стартира. Използвай „Копирай“.');
      }
    }
  }

  Future<void> _openInStudio(SongProject song) async {
    await widget.store.loadSongIntoStudio(song);
    widget.onOpenStudio();
    if (mounted) _showMessage('Песента е заредена в Rap Studio.');
  }

  Future<void> _deleteSong(SongProject song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изтриване на песен'),
        content: Text('Да изтрия ли „${song.title}“?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отказ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Изтрий'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteSong(song.id);
    if (mounted) _showMessage('Песента е изтрита.');
  }

  Future<void> _showSong(SongProject song) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF06140A),
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          song.title,
                          style: const TextStyle(
                            color: ironGreen,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Затвори',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text(song.style)),
                          Chip(label: Text('${song.bpm} BPM')),
                          Chip(label: Text(song.rhymeScheme)),
                        ],
                      ),
                      if (song.theme.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Тема: ${song.theme}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                      if (song.lyrics.trim().isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Текст',
                          style: TextStyle(
                            color: ironGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          cleanMarkdownForDisplay(song.lyrics),
                          style: const TextStyle(height: 1.45),
                        ),
                      ],
                      if (song.musicPrompt.trim().isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Text(
                          'Style of Music',
                          style: TextStyle(
                            color: ironGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          cleanMarkdownForDisplay(song.musicPrompt),
                          style: const TextStyle(height: 1.45),
                        ),
                      ],
                      if (song.excludePrompt.trim().isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Text(
                          'Exclude',
                          style: TextStyle(
                            color: ironGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          cleanMarkdownForDisplay(song.excludePrompt),
                          style: const TextStyle(height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _openInStudio(song);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('В Studio'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copySunoPackage(song),
                        icon: const Icon(Icons.library_music_outlined),
                        label: const Text('Suno пакет'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copySong(song),
                        icon: const Icon(Icons.copy),
                        label: const Text('Копирай всичко'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportSong(song),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('TXT експорт'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final songs = _filteredSongs(widget.store.songProjects);
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
            children: [
              PageTitle(
                eyebrow: 'ЛИЧНА БИБЛИОТЕКА',
                title: 'Моите песни',
                subtitle:
                    '${widget.store.songProjects.length} запазени проекта • локално',
                trailing: IconButton.filledTonal(
                  tooltip: 'Нов проект',
                  onPressed: () async {
                    await widget.store.startNewStudioProject();
                    widget.onOpenStudio();
                  },
                  icon: const Icon(Icons.add, color: ironGreen),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                cursorColor: ironGreen,
                decoration: InputDecoration(
                  hintText: 'Търси песни и проекти...',
                  prefixIcon: const Icon(Icons.search, color: ironGreen),
                  suffixIcon: _query.isEmpty
                      ? const Icon(Icons.tune, color: Colors.white38)
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  NeonPill(
                    text: 'ВСИЧКИ ${songs.length}',
                    icon: Icons.grid_view_rounded,
                    active: true,
                  ),
                  NeonPill(
                    text: 'SUNO',
                    icon: Icons.music_note,
                  ),
                  NeonPill(
                    text: 'DRAFT',
                    icon: Icons.edit_note,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (songs.isEmpty)
                IronCard(
                  bright: true,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      const Icon(
                        Icons.library_music_outlined,
                        color: ironGreen,
                        size: 58,
                      ),
                      const SizedBox(height: 13),
                      Text(
                        _query.isEmpty
                            ? 'Още няма запазени песни.'
                            : 'Няма резултати за това търсене.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_query.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Създай песен в Rap Studio и натисни „Запази песен“.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 17),
                        SizedBox(
                          width: double.infinity,
                          child: IronButton(
                            text: 'ОТВОРИ RAP STUDIO',
                            icon: Icons.auto_awesome,
                            onPressed: widget.onOpenStudio,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                ...songs.map(
                  (song) => _SongProjectCard(
                    song: song,
                    dateLabel: _formatDate(song.updatedAt),
                    onOpen: () => _showSong(song),
                    onEdit: () => _openInStudio(song),
                    onCopy: () => _copySunoPackage(song),
                    onExport: () => _exportSong(song),
                    onDelete: () => _deleteSong(song),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SongProjectCard extends StatelessWidget {
  final SongProject song;
  final String dateLabel;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _SongProjectCard({
    required this.song,
    required this.dateLabel,
    required this.onOpen,
    required this.onEdit,
    required this.onCopy,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final preview = cleanMarkdownForDisplay(
      song.lyrics.trim().isNotEmpty ? song.lyrics : song.musicPrompt,
    );

    return IronCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SongCover(song: song),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        const _MiniTag('Suno', active: true),
                        _MiniTag(song.style),
                        _MiniTag('${song.bpm} BPM'),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: ironGreen),
                onSelected: (value) {
                  if (value == 'open') onOpen();
                  if (value == 'edit') onEdit();
                  if (value == 'copy') onCopy();
                  if (value == 'export') onExport();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Отвори')),
                  PopupMenuItem(value: 'edit', child: Text('Редактирай')),
                  PopupMenuItem(value: 'copy', child: Text('Копирай Suno пакет')),
                  PopupMenuItem(value: 'export', child: Text('TXT експорт')),
                  PopupMenuItem(value: 'delete', child: Text('Изтрий')),
                ],
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.22),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: ironGreen.withOpacity(0.12)),
              ),
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  height: 1.3,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SongAction(
                  icon: Icons.open_in_new,
                  label: 'ОТВОРИ',
                  onTap: onOpen,
                ),
              ),
              Expanded(
                child: _SongAction(
                  icon: Icons.edit_outlined,
                  label: 'РЕДАКТИРАЙ',
                  onTap: onEdit,
                ),
              ),
              Expanded(
                child: _SongAction(
                  icon: Icons.copy_outlined,
                  label: 'КОПИРАЙ',
                  onTap: onCopy,
                ),
              ),
              Expanded(
                child: _SongAction(
                  icon: Icons.ios_share,
                  label: 'ЕКСПОРТ',
                  onTap: onExport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SongCover extends StatelessWidget {
  final SongProject song;

  const _SongCover({required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ironGreen.withOpacity(0.48)),
        boxShadow: [
          BoxShadow(
            color: ironGreen.withOpacity(0.13),
            blurRadius: 14,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _SongCoverPainter(seed: song.title.hashCode)),
            Center(
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.66),
                  border: Border.all(color: ironGreen.withOpacity(0.8)),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: ironGreen,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SongAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Column(
          children: [
            Icon(icon, color: ironGreen, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 8.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongCoverPainter extends CustomPainter {
  final int seed;

  const _SongCoverPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(const Color(0xFF001E0D), const Color(0xFF07361A),
              ((seed.abs() % 70) / 100))!,
          const Color(0xFF010603),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    final line = Paint()
      ..color = ironGreen.withOpacity(0.18)
      ..strokeWidth = 1;
    for (double x = 8; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x - 18, size.height), line);
    }
    for (double y = 12; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final glow = Paint()
      ..color = ironGreen.withOpacity(0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(size.center(Offset.zero), 22, glow);

    final wave = Paint()
      ..color = ironGreen.withOpacity(0.65)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(0, size.height * 0.72);
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.72 +
          math.sin((x + seed.abs() % 20) / 6) * 4;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, wave);
  }

  @override
  bool shouldRepaint(covariant _SongCoverPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class _MiniTag extends StatelessWidget {
  final String text;
  final bool active;

  const _MiniTag(this.text, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return NeonPill(text: text, active: active);
  }
}
