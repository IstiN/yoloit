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
/// as the desktop app.
class BoardTitleBar extends StatelessWidget {
  const BoardTitleBar({
    super.key,
    required this.onSettings,
    this.onDragStart,
    this.leading,
    this.trailing,
    this.afterSettings,
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

  /// Whether the current platform has macOS-style native traffic lights on the
  /// left and therefore needs extra padding.
  static bool get _hasMacOSTrafficLights {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      behavior: HitTestBehavior.translucent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.surface.withAlpha(31),
                  colors.surface.withAlpha(82),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: colors.border.withAlpha(166)),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.textPrimary.withAlpha(46),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(width: _hasMacOSTrafficLights ? 82 : 12),
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
            ),
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
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  State<_PanelToggleButton> createState() => _PanelToggleButtonState();
}

class _PanelToggleButtonState extends State<_PanelToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        label: widget.semanticsLabel ?? widget.tooltip,
        button: true,
        toggled: widget.active,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 32,
              height: 28,
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
                size: 16,
                color: widget.active
                    ? colors.primary
                    : context.appColors.textMuted,
                semanticLabel: widget.tooltip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
