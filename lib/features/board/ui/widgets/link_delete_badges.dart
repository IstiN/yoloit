import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';
import 'package:yoloit/features/board/ui/board_math.dart';

class LinkDeleteBadges extends StatelessWidget {
  const LinkDeleteBadges({
    super.key,
    required this.links,
    required this.panels,
    required this.origin,
  });

  final List<BoardPanelLink> links;
  final List<BoardPanelInstance> panels;
  final Offset origin;

  @override
  Widget build(BuildContext context) {
    final panelMap = {for (final p in panels) p.id: p};

    return Stack(
      children: [
        for (final link in links)
          if (panelMap[link.fromPanelId] != null &&
              panelMap[link.toPanelId] != null &&
              !panelMap[link.fromPanelId]!.hidden &&
              !panelMap[link.toPanelId]!.hidden)
            _LinkDeleteBadge(
              link: link,
              from: panelMap[link.fromPanelId]!,
              to: panelMap[link.toPanelId]!,
              origin: origin,
            ),
      ],
    );
  }
}

class _LinkDeleteBadge extends StatefulWidget {
  const _LinkDeleteBadge({
    required this.link,
    required this.from,
    required this.to,
    required this.origin,
  });

  final BoardPanelLink link;
  final BoardPanelInstance from;
  final BoardPanelInstance to;
  final Offset origin;

  @override
  State<_LinkDeleteBadge> createState() => _LinkDeleteBadgeState();
}

class _LinkDeleteBadgeState extends State<_LinkDeleteBadge> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fromRect = widget.from.bounds.rect.translate(
      widget.origin.dx,
      widget.origin.dy,
    );
    final toRect = widget.to.bounds.rect.translate(
      widget.origin.dx,
      widget.origin.dy,
    );
    final start = BoardLinksPainter.edgePointToward(fromRect, toRect.center);
    final end = BoardLinksPainter.edgePointToward(toRect, fromRect.center);
    final mid = linkMidpoint(start, end, widget.link.geometry);

    const hitR = 24.0;
    const badgeR = 11.0;
    final linkColor = widget.link.color;

    return Positioned(
      left: mid.dx - hitR,
      top: mid.dy - hitR,
      width: hitR * 2,
      height: hitR * 2,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Center(
          child: GestureDetector(
            onTap: () => context.read<BoardCubit>().removeLink(widget.link.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isHovered ? badgeR * 2 : 8,
              height: _isHovered ? badgeR * 2 : 8,
              decoration: BoxDecoration(
                color: _isHovered
                    ? colors.statusError.withAlpha(204)
                    : linkColor.withAlpha(100),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isHovered
                      ? Theme.of(context).colorScheme.onSurface.withAlpha(80)
                      : linkColor.withAlpha(50),
                  width: 1,
                ),
              ),
              child: _isHovered
                  ? Icon(
                      Icons.close,
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
