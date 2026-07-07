import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Shared bottom-right chat drawer used by the YoLo assistant badge.
///
/// Handles the YOLO tab, slide animation, and rounded panel container.
/// The actual chat content is supplied by [panelContent] so the desktop and
/// web badges can use different implementations (native assistant vs web
/// chat panel) without duplicating the shell layout.
class YoloBadgeChatShell extends StatefulWidget {
  const YoloBadgeChatShell({
    super.key,
    required this.isOpen,
    required this.onToggle,
    required this.panelContent,
    this.tabLabel = 'YOLO',
    this.panelHeight = 480,
    this.panelMaxWidth = 380,
  });

  final bool isOpen;
  final VoidCallback onToggle;
  final Widget panelContent;
  final String tabLabel;
  final double panelHeight;
  final double panelMaxWidth;

  @override
  State<YoloBadgeChatShell> createState() => _YoloBadgeChatShellState();
}

class _YoloBadgeChatShellState extends State<YoloBadgeChatShell>
    with TickerProviderStateMixin {
  late final AnimationController _chatController;
  late final Animation<double> _chatSlide;

  @override
  void initState() {
    super.initState();
    _chatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _chatSlide = Tween<double>(begin: 380, end: 0).animate(
      CurvedAnimation(parent: _chatController, curve: Curves.easeOutCubic),
    );
    if (widget.isOpen) _chatController.value = 1.0;
  }

  @override
  void didUpdateWidget(YoloBadgeChatShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen == oldWidget.isOpen) return;
    if (widget.isOpen) {
      _chatController.forward();
    } else {
      _chatController.reverse();
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: _buildChatTab(context),
          ),
          AnimatedBuilder(
            animation: _chatController,
            builder: (context, child) {
              final progress = 1.0 - (_chatSlide.value / 380);
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  boxShadow:
                      progress > 0.05
                          ? [
                            BoxShadow(
                              color: context.appColors.background
                                  .withValues(alpha: 0.14 * progress),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(-8, 8),
                            ),
                          ]
                          : [],
                ),
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: child,
                  ),
                ),
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = MediaQuery.sizeOf(context).width - 44;
                return SizedBox(
                  width: availableWidth.clamp(260.0, widget.panelMaxWidth),
                  height: widget.panelHeight,
                  child: _buildChatPanel(context),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: widget.onToggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.primary, colors.primaryLight],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(-2, 2),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child:
                widget.isOpen
                    ? Icon(Icons.close, size: 14, color: colors.textPrimary)
                    : Text(
                      widget.tabLabel,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.panelContent,
    );
  }
}
