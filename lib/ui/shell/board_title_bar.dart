import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Platform-aware title bar shared between desktop and web.
///
/// On macOS it reserves space on the left for the native traffic lights.
/// On Windows/Linux it leaves a small margin and an optional [trailing] slot
/// is used for custom window controls.
/// On the web it renders the same visual shell without dragging or native
/// window controls.
///
/// A settings button is always shown so the web demo has the same entry point
/// as the desktop app. When [onHistory] is provided a board-history toggle is
/// shown on the left, after the platform window-controls padding.
class BoardTitleBar extends StatelessWidget {
  const BoardTitleBar({
    super.key,
    required this.onSettings,
    this.onDragStart,
    this.leading,
    this.trailing,
    this.afterSettings,
    this.onHistory,
    this.historyActive = false,
    this.onUndo,
    this.onRedo,
  });

  final VoidCallback onSettings;

  /// Called when the user starts a drag gesture on the title bar.
  /// Pass `null` on platforms that do not support custom window dragging
  /// (e.g. the web).
  final VoidCallback? onDragStart;

  /// Widget shown on the left side of the bar, after the platform padding.
  final Widget? leading;

  /// Widget shown on the right side of the bar, before the settings button.
  final Widget? trailing;

  /// Widget shown after the settings button (e.g. custom window controls on
  /// Windows/Linux).
  final Widget? afterSettings;

  /// When non-null, shows a board-history toggle button on the left side of
  /// the bar, right after the platform window-controls padding.
  /// [historyActive] drives its highlighted state.
  final VoidCallback? onHistory;
  final bool historyActive;

  /// Undo/redo for panel changes, shown next to the history toggle on the
  /// left. Null callbacks render the buttons disabled.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// Whether the current platform has macOS-style native traffic lights on the
  /// left and therefore needs extra padding.
  static bool get _hasMacOSTrafficLights {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final content = Row(
      children: [
        SizedBox(width: _hasMacOSTrafficLights ? 82 : 12),
        if (onHistory != null) ...[
          _PanelToggleButton(
            icon: Icons.manage_history_rounded,
            tooltip: historyActive ? 'Hide board history' : 'Show board history',
            semanticsLabel: 'Toggle board history',
            active: historyActive,
            onTap: onHistory!,
          ),
          const SizedBox(width: 8),
        ],
        if (onUndo != null || onRedo != null) ...[
          _PanelToggleButton(
            icon: Icons.undo_rounded,
            tooltip: 'Undo latest panel change',
            semanticsLabel: 'Undo latest panel change',
            active: false,
            onTap: onUndo,
          ),
          const SizedBox(width: 4),
          _PanelToggleButton(
            icon: Icons.redo_rounded,
            tooltip: 'Redo',
            semanticsLabel: 'Redo',
            active: false,
            onTap: onRedo,
          ),
          const SizedBox(width: 8),
        ],
        if (leading != null) leading!,
        const Spacer(),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 8),
        ],
        _PanelToggleButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings (⌘,)',
          semanticsLabel: 'Open settings',
          active: false,
          onTap: onSettings,
        ),
        if (afterSettings != null) ...[
          const SizedBox(width: 8),
          afterSettings!,
        ] else
          const SizedBox(width: 12),
      ],
    );

    // On macOS the native traffic lights are drawn by the OS slightly below
    // the geometric center of the 44px bar, so shift our content down to
    // keep the icons visually aligned with them.
    final alignedContent = _hasMacOSTrafficLights
        ? Padding(padding: const EdgeInsets.only(top: 10), child: content)
        : content;

    if (kIsWeb) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            bottom: BorderSide(color: colors.border),
          ),
        ),
        child: alignedContent,
      );
    }

    return GestureDetector(
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      behavior: HitTestBehavior.translucent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.surface.withAlpha(120),
                  colors.surface.withAlpha(200),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: alignedContent,
          ),
        ),
      ),
    );
  }
}

class _PanelToggleButton extends StatefulWidget {
  const _PanelToggleButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final String tooltip;
  final bool active;

  /// Null disables the button (dimmed icon, no tap handling).
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  State<_PanelToggleButton> createState() => _PanelToggleButtonState();
}

class _PanelToggleButtonState extends State<_PanelToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        label: widget.semanticsLabel ?? widget.tooltip,
        button: true,
        toggled: widget.active,
        enabled: enabled,
        child: MouseRegion(
          onEnter: (_) {
            if (enabled) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.active
                    ? colors.primary.withAlpha(46)
                    : _hovered
                        ? colors.surfaceHighlight.withAlpha(153)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: widget.active
                    ? Border.all(color: colors.primary.withAlpha(64))
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: widget.active
                    ? colors.primary
                    : enabled
                        ? context.appColors.textMuted
                        : context.appColors.textMuted.withAlpha(90),
                semanticLabel: widget.tooltip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
