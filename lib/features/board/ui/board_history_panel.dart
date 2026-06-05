import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardHistoryPanel extends StatefulWidget {
  const BoardHistoryPanel({required this.board, required this.onClose});

  final BoardDocument board;
  final VoidCallback onClose;

  @override
  State<BoardHistoryPanel> createState() => BoardHistoryPanelState();
}

class BoardHistoryPanelState extends State<BoardHistoryPanel> {
  late Future<List<BoardHistoryEvent>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
  }

  @override
  void didUpdateWidget(covariant BoardHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.board.id != widget.board.id) {
      _eventsFuture = _loadEvents();
    }
  }

  Future<List<BoardHistoryEvent>> _loadEvents() {
    return context.read<BoardCubit>().historyForBoard(widget.board.id);
  }

  void _refresh() {
    setState(() {
      _eventsFuture = _loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final surface = isLight ? Colors.white : colors.surfaceElevated;
    final textColor =
        isLight
            ? const Color(0xFF252A31)
            : Theme.of(context).colorScheme.onSurface;
    final mutedColor = isLight ? const Color(0xFF687083) : colors.textMuted;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border.withAlpha(180)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isLight ? 28 : 110),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.manage_history_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Board history',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh history',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close history',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border.withAlpha(150)),
            Expanded(
              child: FutureBuilder<List<BoardHistoryEvent>>(
                future: _eventsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final events =
                      (snapshot.data ?? const <BoardHistoryEvent>[]).reversed
                          .toList();
                  if (events.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No board changes recorded yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedColor, fontSize: 13),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: events.length,
                    separatorBuilder:
                        (_, __) => Divider(
                          height: 10,
                          color: colors.border.withAlpha(90),
                        ),
                    itemBuilder:
                        (context, index) => BoardHistoryEventTile(
                          event: events[index],
                          textColor: textColor,
                          mutedColor: mutedColor,
                          onRestore:
                              events[index].entityType == 'panel' &&
                                      (events[index].before != null ||
                                          events[index].after != null)
                                  ? () async {
                                    await context
                                        .read<BoardCubit>()
                                        .restorePanelFromEvent(
                                          widget.board.id,
                                          events[index].opId,
                                        );
                                    _refresh();
                                  }
                                  : null,
                        ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BoardHistoryEventTile extends StatelessWidget {
  const BoardHistoryEventTile({
    required this.event,
    required this.textColor,
    required this.mutedColor,
    this.onRestore,
  });

  final BoardHistoryEvent event;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final title = _historyEventTitle(event);
    final previewSnapshot = event.before ?? event.after;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HistoryPanelPreview(
            event: event,
            snapshot: previewSnapshot,
            fallbackIcon: _historyEventIcon(event),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'r${event.revision} · ${_formatHistoryTime(event.timestamp)} · ${event.actorId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onRestore != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRestore,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Restore'),
            ),
          ],
        ],
      ),
    );
  }

  static String _historyEventTitle(BoardHistoryEvent event) {
    final snapshot = event.after ?? event.before ?? const <String, dynamic>{};
    final rawTitle = snapshot['title'];
    final entityTitle =
        rawTitle is String && rawTitle.trim().isNotEmpty
            ? rawTitle.trim()
            : event.entityId;
    final action = switch (event.type) {
      'create' => 'Created',
      'update' => 'Updated',
      'delete' => 'Deleted',
      'restore' => 'Restored',
      _ =>
        event.type.isEmpty
            ? 'Changed'
            : '${event.type[0].toUpperCase()}${event.type.substring(1)}',
    };
    return '$action $entityTitle';
  }

  static IconData _historyEventIcon(BoardHistoryEvent event) {
    if (event.entityType == 'panel') {
      return switch (event.type) {
        'create' => Icons.add_box_outlined,
        'delete' => Icons.delete_outline_rounded,
        'restore' => Icons.restore_rounded,
        _ => Icons.dashboard_customize_outlined,
      };
    }
    if (event.entityType == 'link') return Icons.arrow_outward_rounded;
    if (event.entityType == 'drawing') return Icons.edit_outlined;
    return Icons.history_rounded;
  }

  static String _formatHistoryTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class HistoryPanelPreview extends StatelessWidget {
  const HistoryPanelPreview({
    required this.event,
    required this.snapshot,
    required this.fallbackIcon,
  });

  final BoardHistoryEvent event;
  final Map<String, dynamic>? snapshot;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panel = _readPanel(snapshot);
    final state = panel?.state ?? const <String, dynamic>{};
    final shape = state['shape'] as String?;
    final isSticky = panel?.type == 'board.sticky';
    final color =
        panel?.color ?? (isSticky ? colors.statusWarning : colors.primary);

    return Container(
      width: 48,
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withAlpha(180)),
      ),
      child: CustomPaint(
        painter: HistoryPanelPreviewPainter(
          icon: panel == null ? fallbackIcon : null,
          color: color,
          iconColor: colors.primary,
          shape: shape,
          isSticky: isSticky,
          deleted: event.type == 'panel.deleted',
        ),
      ),
    );
  }

  BoardPanelInstance? _readPanel(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return null;
    try {
      return BoardPanelInstance.fromJson(snapshot);
    } catch (_) {
      return null;
    }
  }
}

class HistoryPanelPreviewPainter extends CustomPainter {
  const HistoryPanelPreviewPainter({
    required this.color,
    required this.iconColor,
    required this.isSticky,
    required this.deleted,
    this.icon,
    this.shape,
  });

  final IconData? icon;
  final Color color;
  final Color iconColor;
  final String? shape;
  final bool isSticky;
  final bool deleted;

  @override
  void paint(Canvas canvas, Size size) {
    if (icon != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon!.codePoint),
          style: TextStyle(
            fontFamily: icon!.fontFamily,
            package: icon!.fontPackage,
            fontSize: 18,
            color: iconColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final rect = Rect.fromLTWH(8, 7, size.width - 16, size.height - 14);
    final paint =
        Paint()
          ..color = deleted ? color.withAlpha(90) : color.withAlpha(210)
          ..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..color = deleted ? iconColor.withAlpha(120) : iconColor
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;

    if (isSticky) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        stroke,
      );
    } else if (shape == 'diamond') {
      final path =
          Path()
            ..moveTo(rect.center.dx, rect.top)
            ..lineTo(rect.right, rect.center.dy)
            ..lineTo(rect.center.dx, rect.bottom)
            ..lineTo(rect.left, rect.center.dy)
            ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, stroke);
    } else if (shape == 'circle') {
      canvas.drawOval(rect, paint);
      canvas.drawOval(rect, stroke);
    } else if (shape == 'triangle') {
      final path =
          Path()
            ..moveTo(rect.center.dx, rect.top)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, stroke);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        stroke,
      );
    }

    if (deleted) {
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.right, rect.top),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HistoryPanelPreviewPainter oldDelegate) {
    return oldDelegate.icon != icon ||
        oldDelegate.color != color ||
        oldDelegate.iconColor != iconColor ||
        oldDelegate.shape != shape ||
        oldDelegate.isSticky != isSticky ||
        oldDelegate.deleted != deleted;
  }
}
