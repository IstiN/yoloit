import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';

class BoardSwitchPreviewOverlay extends StatelessWidget {
  const BoardSwitchPreviewOverlay({
    super.key,
    required this.board,
    required this.previewPng,
    required this.visible,
    required this.onHidden,
  });

  final BoardDocument board;
  final Uint8List? previewPng;
  final bool visible;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        onEnd: onHidden,
        child:
            previewPng != null
                ? RepaintBoundary(
                  child: Image.memory(
                    previewPng!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder:
                        (_, _, _) => ColoredBox(
                          color: colors.background,
                          child: const SizedBox.expand(),
                        ),
                  ),
                )
                : ColoredBox(
                  color: colors.background,
                  child: const SizedBox.expand(),
                ),
      ),
    );
  }
}

class BoardOverviewBackdropPainter extends CustomPainter {
  const BoardOverviewBackdropPainter({
    required this.minorColor,
    required this.majorColor,
  });

  final Color minorColor;
  final Color majorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final minorPaint =
        Paint()
          ..color = minorColor
          ..strokeWidth = 1;
    final majorPaint =
        Paint()
          ..color = majorColor
          ..strokeWidth = 1;
    const minorStep = 28.0;
    const majorEvery = 4;
    for (var x = 0.0, i = 0; x <= size.width; x += minorStep, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % majorEvery == 0 ? majorPaint : minorPaint,
      );
    }
    for (var y = 0.0, i = 0; y <= size.height; y += minorStep, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % majorEvery == 0 ? majorPaint : minorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardOverviewBackdropPainter oldDelegate) {
    return oldDelegate.minorColor != minorColor ||
        oldDelegate.majorColor != majorColor;
  }
}

class BoardOverviewSectionLabel extends StatelessWidget {
  const BoardOverviewSectionLabel({
    super.key,
    required this.rect,
    required this.label,
    required this.opacity,
    this.subtitle,
    this.disconnectKey,
    this.onDisconnect,
  });

  final Rect rect;
  final String label;
  final String? subtitle;
  final double opacity;
  final Key? disconnectKey;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Positioned(
      left: rect.left,
      top: math.max(10, rect.top - 32),
      child: Opacity(
        opacity: opacity,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: colors.textMuted.withAlpha(150),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (onDisconnect != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Tooltip(
                    message: 'Disconnect remote boards',
                    child: InkWell(
                      key: disconnectKey,
                      borderRadius: BorderRadius.circular(6),
                      onTap: onDisconnect,
                      child: Icon(
                        Icons.link_off_rounded,
                        size: 14,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BoardOverviewCard extends StatelessWidget {
  const BoardOverviewCard({
    super.key,
    required this.board,
    required this.active,
    required this.previewPng,
    required this.onTap,
    this.onDisconnect,
    this.onDeleteRemote,
  });

  final BoardDocument board;
  final bool active;
  final Uint8List? previewPng;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;
  final VoidCallback? onDeleteRemote;

  @override
  Widget build(BuildContext context) {
    final (colors, textColor, mutedColor) = boardTextColors(context);
    final remote = remoteInfoForBoard(board);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? colors.textPrimary.withAlpha(90) : colors.border,
            width: active ? 1.2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            children: [
              SizedBox(
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    border: Border(bottom: BorderSide(color: colors.divider)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (active) ...[
                          Icon(
                            Icons.radio_button_checked,
                            size: 14,
                            color: colors.textPrimary.withAlpha(180),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            board.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (remote != null) ...[
                          Tooltip(
                            message: remote.url,
                            child: Icon(
                              Icons.cloud_outlined,
                              size: 14,
                              color: mutedColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          '${board.panels.length}',
                          style: TextStyle(color: mutedColor, fontSize: 11),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.widgets_outlined,
                          size: 13,
                          color: mutedColor,
                        ),
                        if (onDisconnect != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Disconnect remote board',
                            child: InkResponse(
                              key: Key('board-overview-disconnect-${board.id}'),
                              radius: 14,
                              onTap: onDisconnect,
                              child: Icon(
                                Icons.link_off_rounded,
                                size: 14,
                                color: mutedColor,
                              ),
                            ),
                          ),
                        ],
                        if (onDeleteRemote != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Delete board on remote server',
                            child: InkResponse(
                              key: Key(
                                'board-overview-delete-remote-${board.id}',
                              ),
                              radius: 14,
                              onTap: onDeleteRemote,
                              child: Icon(
                                Icons.delete_outline,
                                size: 14,
                                color: colors.accentRed,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child:
                    previewPng == null
                        ? BoardOverviewPreview(board: board)
                        : BoardOverviewPngPreview(
                          bytes: previewPng!,
                          fallback: BoardOverviewPreview(board: board),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateBoardOverviewCard extends StatelessWidget {
  const CreateBoardOverviewCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = context.appColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface.withAlpha(190),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                size: 46,
                color: mutedColor.withAlpha(180),
              ),
              const SizedBox(height: 8),
              Text(
                'New board',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BoardOverviewPngPreview extends StatelessWidget {
  const BoardOverviewPngPreview({super.key, required this.bytes, required this.fallback});

  final Uint8List bytes;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Plain background — fallback only shown on image error.
        ColoredBox(color: context.appColors.background),
        RepaintBoundary(
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                context.appColors.background.withAlpha(45),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
