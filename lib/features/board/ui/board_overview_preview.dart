import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

class BoardOverviewPreview extends StatelessWidget {
  const BoardOverviewPreview({required this.board});

  final BoardDocument board;

  /// Standard viewport size used when computing visible bounds from saved
  /// viewport state. Approximates a typical MacBook screen size.
  static const Size _standardViewportSize = Size(1440, 900);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panels = board.panels.where((panel) => !panel.hidden).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (panels.isEmpty) {
          return ColoredBox(
            color: colors.background,
            child: Center(
              child: Container(
                width: math.min(size.width, 120),
                height: math.min(size.height, 70),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(
                  Icons.dashboard_outlined,
                  color:
                      Theme.of(context).textTheme.bodySmall?.color ??
                      Theme.of(context).colorScheme.onSurface,
                  size: 26,
                ),
              ),
            ),
          );
        }

        // If the user has saved a non-default viewport (zoomed / panned),
        // show the board from that saved position instead of fitting all.
        // Otherwise fall back to fit-all.
        final vp = board.viewport;
        final Rect bounds;
        if (_isNonDefaultViewport(vp)) {
          bounds = _visibleBoundsFromViewport(vp);
        } else {
          bounds = boundsForPanels(panels).inflate(120);
        }

        final scale = math.min(
          size.width / bounds.width,
          size.height / bounds.height,
        );
        final dx = (size.width - bounds.width * scale) / 2;
        final dy = (size.height - bounds.height * scale) / 2;

        return ColoredBox(
          color: colors.background,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: BoardOverviewLinksPainter(
                    links: board.links,
                    panels: panels,
                    bounds: bounds,
                    scale: scale,
                    dx: dx,
                    dy: dy,
                  ),
                ),
              ),
              for (final panel in panels)
                Positioned.fromRect(
                  rect: mapPanelRect(panel.bounds.rect, bounds, scale, dx, dy),
                  child: BoardOverviewPanelPreview(panel: panel),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _isNonDefaultViewport(BoardViewport vp) {
    // Consider non-default if scale deviates significantly from 1.0 or
    // user has panned more than a minimal amount.
    return vp.scale != 1.0 || vp.translation != Offset.zero;
  }

  /// Compute the visible board-coordinate rect from the saved viewport.
  ///
  /// The board uses transform: screenPos = boardPos * scale + translation
  /// (canvas origin is already folded into translation by _saveViewport).
  /// So the visible board rect at a standard 1440×900 viewport is:
  ///   left = -translation.dx / scale
  ///   top  = -translation.dy / scale
  ///   size = standardViewportSize / scale
  Rect _visibleBoundsFromViewport(BoardViewport vp) {
    final s = vp.scale;
    final tx = vp.translation.dx;
    final ty = vp.translation.dy;
    final vw = _standardViewportSize.width;
    final vh = _standardViewportSize.height;
    return Rect.fromLTWH(-tx / s, -ty / s, vw / s, vh / s);
  }

  Rect boundsForPanels(List<BoardPanelInstance> panels) {
    var bounds = panels.first.bounds.rect;
    for (final panel in panels.skip(1)) {
      bounds = bounds.expandToInclude(panel.bounds.rect);
    }
    return bounds;
  }

  Rect mapPanelRect(Rect rect, Rect bounds, double scale, double dx, double dy) {
    return Rect.fromLTWH(
      dx + (rect.left - bounds.left) * scale,
      dy + (rect.top - bounds.top) * scale,
      math.max(12, rect.width * scale),
      math.max(9, rect.height * scale),
    );
  }
}

class BoardOverviewLinksPainter extends CustomPainter {
  const BoardOverviewLinksPainter({
    required this.links,
    required this.panels,
    required this.bounds,
    required this.scale,
    required this.dx,
    required this.dy,
  });

  final List<BoardPanelLink> links;
  final List<BoardPanelInstance> panels;
  final Rect bounds;
  final double scale;
  final double dx;
  final double dy;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final from = panels.where((p) => p.id == link.fromPanelId).firstOrNull;
      final to = panels.where((p) => p.id == link.toPanelId).firstOrNull;
      if (from == null || to == null) continue;
      canvas.drawLine(
        _mapPoint(from.bounds.rect.center),
        _mapPoint(to.bounds.rect.center),
        Paint()
          ..color = link.color.withAlpha(120)
          ..strokeWidth = 1.2,
      );
    }
  }

  Offset _mapPoint(Offset point) {
    return Offset(
      dx + (point.dx - bounds.left) * scale,
      dy + (point.dy - bounds.top) * scale,
    );
  }

  @override
  bool shouldRepaint(covariant BoardOverviewLinksPainter oldDelegate) {
    return oldDelegate.links != links ||
        oldDelegate.panels != panels ||
        oldDelegate.bounds != bounds ||
        oldDelegate.scale != scale ||
        oldDelegate.dx != dx ||
        oldDelegate.dy != dy;
  }
}

class BoardOverviewPanelPreview extends StatelessWidget {
  const BoardOverviewPanelPreview({required this.panel});

  final BoardPanelInstance panel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 54 || constraints.maxHeight < 38;
        final textColor = Theme.of(context).colorScheme.onSurface;
        final muted =
            Theme.of(context).textTheme.bodySmall?.color ??
            textColor.withAlpha(140);
        return ClipRRect(
          borderRadius: BorderRadius.circular(tiny ? 3 : 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(tiny ? 3 : 6),
              border: Border.all(color: colors.divider, width: 0.5),
            ),
            child:
                tiny
                    ? const SizedBox.expand()
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          color: colors.divider.withAlpha(30),
                          child: Row(
                            children: [
                              Icon(
                                iconForPanelType(panel.type),
                                size: 9,
                                color: muted,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  panel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: OverflowBox(
                              maxHeight: double.infinity,
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: BoardOverviewPanelContent(panel: panel),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
          ),
        );
      },
    );
  }
}

class BoardOverviewPanelContent extends StatelessWidget {
  const BoardOverviewPanelContent({required this.panel});

  final BoardPanelInstance panel;

  @override
  Widget build(BuildContext context) {
    final state = panel.state;
    return switch (panel.type) {
      'board.note.markdown' => _linesContent(
        context,
        _plainText(state['markdown']).split(RegExp(r'\n+')).take(5).toList(),
      ),
      'board.checklist' => _checklistContent(context, state['items']),
      'board.kanban' => _kanbanContent(context, state),
      'board.code.snippet' => _codeContent(context, state),
      'board.files' => _namedListContent(
        context,
        state['files'],
        Icons.insert_drive_file_outlined,
      ),
      'board.playlist' => _namedListContent(
        context,
        state['tracks'],
        Icons.music_note_outlined,
      ),
      'board.filetree' => _filetreeContent(context, state),
      'board.file.preview' => _filePreviewContent(context, state),
      'board.diff.preview' => _diffContent(context, state),
      'board.webpage' => _webPageContent(context, state),
      'board.chat' => _chatContent(context, state),
      'board.terminal' => _terminalContent(context, state),
      'board.yolo_assistant' => _chatContent(context, state),
      'board.timer' => _timerContent(context, state),
      _ => Center(
        child: Icon(
          iconForPanelType(panel.type),
          color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
          size: 18,
        ),
      ),
    };
  }

  Widget _linesContent(BuildContext context, List<String> lines) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final clean =
        lines
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .take(5)
            .toList();
    if (clean.isEmpty) {
      return _placeholderContent(
        context,
        Icons.notes_outlined,
        'Note',
        'Empty',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in clean)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor.withAlpha(215),
                fontSize: 7,
                height: 1.05,
              ),
            ),
          ),
      ],
    );
  }

  Widget _checklistContent(BuildContext context, Object? rawItems) {
    final items = _maps(rawItems);
    if (items.isEmpty) {
      return _placeholderContent(
        context,
        Icons.checklist_outlined,
        'Checklist',
        'No items',
      );
    }
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  (item['done'] as bool? ?? false)
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 8,
                  color: textColor.withAlpha(140),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    item['text']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withAlpha(215),
                      fontSize: 7,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kanbanContent(BuildContext context, Map<String, dynamic> state) {
    final columns =
        (state['columns'] as List?)
            ?.map((e) => e.toString())
            .take(4)
            .toList() ??
        const ['Backlog', 'Todo', 'In Progress', 'Done'];
    final cards = _maps(state['cards']);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            Expanded(
              child: _miniKanbanColumn(
                context,
                columns[i],
                cards.where((c) => (c['columnIndex'] as int? ?? 0) == i).toList(),
              ),
            ),
            if (i != columns.length - 1) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }

  Widget _miniKanbanColumn(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> cards,
  ) {
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withAlpha(165),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor.withAlpha(220),
                fontSize: 6.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            for (final card in cards.take(3))
              Container(
                height: 8,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: colors.surface.withAlpha(220),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  card['title']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: textColor.withAlpha(170),
                    fontSize: 4.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeContent(BuildContext context, Map<String, dynamic> state) {
    final code = state['code']?.toString().trim() ?? '';
    final language = state['language']?.toString() ?? 'code';
    if (code.isEmpty) {
      return _placeholderContent(
        context,
        Icons.code_outlined,
        language,
        'Empty',
      );
    }
    final lines = code.split('\n').take(5).toList();
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          language,
          style: TextStyle(
            color: textColor.withAlpha(140),
            fontSize: 6.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        for (final line in lines)
          Text(
            line.trimRight(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: textColor.withAlpha(190),
              fontSize: 6,
              fontFamily: 'monospace',
              height: 1.05,
            ),
          ),
      ],
    );
  }

  Widget _namedListContent(BuildContext context, Object? raw, IconData icon) {
    final items = _maps(raw);
    if (items.isEmpty) {
      return _placeholderContent(context, icon, panel.title, 'No items');
    }
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 8,
                  color: textColor.withAlpha(140),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    item['name']?.toString() ??
                        item['title']?.toString() ??
                        _basename(item['path']?.toString() ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withAlpha(215),
                      fontSize: 7,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _webPageContent(BuildContext context, Map<String, dynamic> state) {
    final url = state['url'] as String? ?? '';
    final title = state['title'] as String? ?? '';
    final host = _hostForUrl(url);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: muted.withAlpha(20),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Icon(Icons.language_outlined, size: 7, color: muted.withAlpha(160)),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  host.isNotEmpty ? host : url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted.withAlpha(160), fontSize: 6.5),
                ),
              ),
            ],
          ),
        ),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor.withAlpha(215),
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (url.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No URL',
              style: TextStyle(color: muted.withAlpha(140), fontSize: 6.5),
            ),
          ),
      ],
    );
  }

  Widget _chatContent(BuildContext context, Map<String, dynamic> state) {
    final messages = _maps(state['messages'])
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .toList();
    if (messages.isEmpty) {
      return _placeholderContent(
        context,
        Icons.auto_awesome,
        'AI Chat',
        'No messages',
      );
    }
    final recent = messages.length > 4
        ? messages.sublist(messages.length - 4)
        : messages;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final msg in recent) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 7,
                margin: const EdgeInsets.only(top: 1, right: 2),
                decoration: BoxDecoration(
                  color: msg['role'] == 'user'
                      ? const Color(0xFF7C3AED).withAlpha(160)
                      : muted.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    msg['role'] == 'user' ? 'U' : 'AI',
                    style: TextStyle(
                      color: msg['role'] == 'user'
                          ? Colors.white.withAlpha(220)
                          : muted.withAlpha(180),
                      fontSize: 4.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _plainText(msg['content']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withAlpha(200),
                    fontSize: 6.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ],
    );
  }

  Widget _terminalContent(BuildContext context, Map<String, dynamic> state) {
    final config = state['config'];
    String sessionName = '';
    String workingDir = '';
    if (config is Map) {
      sessionName = config['sessionName']?.toString() ?? '';
      workingDir = config['workingDir']?.toString() ?? '';
    }
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.terminal, size: 8, color: const Color(0xFF4ADE80).withAlpha(200)),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                sessionName.isNotEmpty ? sessionName : 'shell',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF4ADE80).withAlpha(200),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (workingDir.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '~ ${_basename(workingDir)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted.withAlpha(160), fontSize: 6.5),
          ),
        ],
      ],
    );
  }

  Widget _filetreeContent(BuildContext context, Map<String, dynamic> state) {
    final rootPath = state['rootPath'] as String? ?? '';
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 9, color: const Color(0xFFFACC15).withAlpha(200)),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                rootPath.isEmpty ? 'No folder' : _basename(rootPath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withAlpha(215),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (rootPath.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            rootPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted.withAlpha(130), fontSize: 5.5),
          ),
        ],
      ],
    );
  }

  Widget _filePreviewContent(BuildContext context, Map<String, dynamic> state) {
    final path = state['path'] as String? ?? '';
    final title = state['title'] as String? ?? '';
    final name = title.isNotEmpty ? title : _basename(path);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              _iconForExt(ext),
              size: 9,
              color: _colorForExt(ext).withAlpha(200),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                name.isEmpty ? 'File Preview' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withAlpha(215),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (path.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _dirName(path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted.withAlpha(130), fontSize: 5.5),
          ),
        ],
      ],
    );
  }

  Widget _diffContent(BuildContext context, Map<String, dynamic> state) {
    final filePath = state['filePath'] as String? ?? '';
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).textTheme.bodySmall?.color ?? textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.difference_outlined, size: 9, color: const Color(0xFF60A5FA).withAlpha(200)),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                _basename(filePath).isEmpty ? 'Diff' : _basename(filePath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withAlpha(215),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (filePath.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _dirName(filePath),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted.withAlpha(130), fontSize: 5.5),
          ),
        ],
      ],
    );
  }

  IconData _iconForExt(String ext) {
    return switch (ext) {
      'dart' || 'js' || 'ts' || 'py' || 'go' || 'rs' || 'java' || 'kt' ||
      'swift' || 'c' || 'cpp' || 'h' => Icons.code_outlined,
      'md' || 'txt' || 'log' => Icons.description_outlined,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => Icons.image_outlined,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  Color _colorForExt(String ext) {
    return switch (ext) {
      'dart' => const Color(0xFF54C5F8),
      'js' || 'ts' => const Color(0xFFF0DB4F),
      'py' => const Color(0xFF4B8BBE),
      'md' || 'txt' => const Color(0xFF9CA3AF),
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => const Color(0xFFF472B6),
      'json' || 'yaml' || 'yml' => const Color(0xFF34D399),
      _ => const Color(0xFF9CA3AF),
    };
  }

  String _dirName(String path) {
    if (path.isEmpty) return '';
    final sep = path.contains('/') ? '/' : r'\';
    final parts = path.split(sep);
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join(sep);
  }

  Widget _timerContent(BuildContext context, Map<String, dynamic> state) {
    final remaining =
        state['remaining'] as int? ?? state['duration'] as int? ?? 0;
    final label = state['label'] as String? ?? 'Timer';
    final minutes = (remaining / 60).floor();
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return _placeholderContent(
      context,
      Icons.timer_outlined,
      label.isEmpty ? 'Timer' : label,
      '$minutes:$seconds',
    );
  }

  Widget _placeholderContent(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final muted =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: muted.withAlpha(180)),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor.withAlpha(220),
              fontSize: 7.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.trim().isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted.withAlpha(185), fontSize: 6.4),
            ),
        ],
      ),
    );
  }


  List<Map<String, dynamic>> _maps(Object? raw) {
    return (raw as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];
  }

  String _plainText(Object? raw) {
    return (raw?.toString() ?? '')
        .replaceAll(RegExp(r'[#*_>`\[\]()]'), ' ')
        .trim();
  }

  String _basename(String value) {
    if (value.trim().isEmpty) return '';
    final normalized = value.replaceAll('\\', '/');
    return normalized.split('/').where((part) => part.isNotEmpty).lastOrNull ??
        value;
  }

  String _hostForUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri?.host ?? '';
  }
}

Color panelTypeColor(String type, {Color? override}) {
  if (override != null) return override;
  return switch (type) {
    'board.note.markdown' => const Color(0xFFE879F9),
    'board.kanban' => const Color(0xFF6366F1),
    'board.webpage' => const Color(0xFF0EA5E9),
    'board.code.snippet' => const Color(0xFF10B981),
    'board.checklist' => const Color(0xFFF59E0B),
    'board.files' => const Color(0xFFEC4899),
    'board.file.preview' => const Color(0xFF8B5CF6),
    'board.playlist' => const Color(0xFFA855F7),
    'board.run_configs' => const Color(0xFF22C55E),
    'board.run' => const Color(0xFF84CC16),
    'board.chat' => const Color(0xFF34D399),
    'board.terminal' => const Color(0xFF14B8A6),
    'board.filetree' => const Color(0xFF64748B),
    'board.diff.preview' => const Color(0xFF60A5FA),
    'board.yolo_assistant' => const Color(0xFFF97316),
    'board.widget.custom' => const Color(0xFF7C3AED),
    'board.timer' => const Color(0xFF3B82F6),
    _ => const Color(0xFF94A3B8),
  };
}

IconData iconForPanelType(String type) {
  return BoardPluginRegistry.instance.pluginFor(type)?.icon ??
      Icons.widgets_outlined;
}
