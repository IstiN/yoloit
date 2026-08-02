import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_scope.dart';

/// Right-edge YoLo trigger for board panels: subtle strip → hover badge.
class PanelYoloAssistantBadge extends StatefulWidget {
  const PanelYoloAssistantBadge({
    super.key,
    required this.targetPanel,
    required this.assistantOpen,
    this.highlighted = false,
  });

  final BoardPanelInstance targetPanel;
  final bool assistantOpen;
  final bool highlighted;

  static const double stripWidth = 5;
  static const double badgeWidth = 34;
  static const double hitWidth = 22;
  static const double minTriggerHeight = 88;
  static const double expandedWidth = 360;
  static const double expandedHeight = 420;

  /// Legacy alias used by older layout/tests.
  static const double badgeSize = badgeWidth;

  @override
  State<PanelYoloAssistantBadge> createState() =>
      _PanelYoloAssistantBadgeState();
}

class _PanelYoloAssistantBadgeState extends State<PanelYoloAssistantBadge> {
  bool _hovered = false;
  Timer? _hoverCollapseTimer;

  @override
  void dispose() {
    _hoverCollapseTimer?.cancel();
    super.dispose();
  }

  void _openAssistant({bool startMic = false}) {
    if (widget.assistantOpen) {
      context.read<BoardCubit>().closeYoloAssistant();
      return;
    }
    context.read<BoardCubit>().openYoloAssistant(
      widget.targetPanel.id,
      startMic: startMic,
    );
  }

  void _onHoverEnter() {
    _hoverCollapseTimer?.cancel();
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onHoverExit() {
    _hoverCollapseTimer?.cancel();
    _hoverCollapseTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted && !widget.assistantOpen) {
        setState(() => _hovered = false);
      }
    });
  }

  void _onMicTap() {
    final controller = YoloAnchoredAssistantScope.controllerFor(
      context,
      widget.targetPanel.id,
    );
    if (controller != null) {
      unawaited(controller.startMic());
      return;
    }
    _openAssistant(startMic: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final showBadge = _hovered || widget.highlighted || widget.assistantOpen;
    final idleOpacity = widget.highlighted ? 0.72 : 0.38;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = _heightFor(constraints);
        final docked = widget.assistantOpen;
        return Semantics(
          button: true,
          label:
              docked
                  ? 'Close YoLo assistant'
                  : 'Ask YoLo about this panel',
          onTap: _openAssistant,
          child: SizedBox(
            width:
                docked
                    ? PanelYoloAssistantBadge.badgeWidth
                    : PanelYoloAssistantBadge.hitWidth,
            height: height,
            child: MouseRegion(
              onEnter: (_) => _onHoverEnter(),
              onExit: (_) => _onHoverExit(),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openAssistant,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    _buildTrigger(
                      colors,
                      height: height,
                      docked: docked,
                      showBadge: showBadge,
                      idleOpacity: idleOpacity,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _heightFor(BoxConstraints constraints) =>
      constraints.maxHeight.isFinite && constraints.maxHeight > 0
          ? constraints.maxHeight
          : PanelYoloAssistantBadge.minTriggerHeight;

  Widget _buildTrigger(
    AppColorScheme colors, {
    required double height,
    required bool docked,
    required bool showBadge,
    required double idleOpacity,
  }) {
    final visualWidth =
        showBadge
            ? PanelYoloAssistantBadge.badgeWidth
            : PanelYoloAssistantBadge.stripWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: visualWidth,
      height: height,
      decoration: BoxDecoration(
        borderRadius: _borderRadius(docked: docked, showBadge: showBadge),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.accentBlue.withValues(
              alpha: showBadge ? 0.95 : idleOpacity,
            ),
            colors.primary.withValues(
              alpha: showBadge ? 0.95 : idleOpacity,
            ),
          ],
        ),
        boxShadow: _boxShadow(colors, docked: docked, showBadge: showBadge),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _switcherChild(
          colors,
          height: height,
          docked: docked,
          showBadge: showBadge,
        ),
      ),
    );
  }

  BorderRadius _borderRadius({required bool docked, required bool showBadge}) =>
      docked
          ? const BorderRadius.horizontal(
            left: Radius.circular(2),
            right: Radius.zero,
          )
          : BorderRadius.horizontal(
            left: const Radius.circular(2),
            right: Radius.circular(showBadge ? 10 : 3),
          );

  List<BoxShadow>? _boxShadow(
    AppColorScheme colors, {
    required bool docked,
    required bool showBadge,
  }) =>
      showBadge && !docked
          ? [
            BoxShadow(
              color: colors.textMuted.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
          : null;

  Widget _switcherChild(
    AppColorScheme colors, {
    required double height,
    required bool docked,
    required bool showBadge,
  }) =>
      showBadge
          ? YoloEdgeBadgeMorphContent(
            key: const ValueKey('yolo-edge-badge'),
            height: height,
            colors: colors,
            showMic: !docked,
            showDockedArrow: docked,
            onMicTap: docked ? null : _onMicTap,
          )
          : const SizedBox(
            key: ValueKey('yolo-edge-strip'),
            width: double.infinity,
          );
}

class YoloEdgeBadgeMorphContent extends StatelessWidget {
  const YoloEdgeBadgeMorphContent({
    super.key,
    required this.height,
    required this.colors,
    this.showMic = true,
    this.showDockedArrow = false,
    this.onMicTap,
  });

  final double height;
  final AppColorScheme colors;
  final bool showMic;
  final bool showDockedArrow;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    final compact = height < 96;
    final micSize = compact ? 10.0 : 12.0;
    final micButtonSize = compact ? 18.0 : 22.0;
    final labelSize = compact ? 8.5 : 10.0;
    final verticalPadding = compact ? 2.0 : 5.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment:
            showMic || showDockedArrow
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
        children: [
          Flexible(
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'YOLO',
                  style: TextStyle(
                    color: colors.textHighlight,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          if (showMic && onMicTap != null)
            Material(
              color: colors.surface.withValues(alpha: 0.22),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onMicTap,
                child: SizedBox(
                  width: micButtonSize,
                  height: micButtonSize,
                  child: Center(
                    child: Icon(
                      Icons.mic_rounded,
                      size: micSize,
                      color: colors.textHighlight,
                    ),
                  ),
                ),
              ),
            ),
          if (showDockedArrow)
            SizedBox(
              width: micButtonSize,
              height: micButtonSize,
              child: Center(
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: micSize + 2,
                  color: colors.textHighlight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
