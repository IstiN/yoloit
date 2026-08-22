import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';
import 'package:yoloit/ui/components/menus/panel_overflow_menu.dart';

/// Unified header bar for board panels.
///
/// Always shows the primary actions (duplicate, lock, color) and a close
/// button. Secondary actions live in the hover-reveal overflow menu.
/// Double-tap the title to rename inline.
class UnifiedPanelHeader extends StatefulWidget {
  const UnifiedPanelHeader({
    required this.panel,
    required this.isSelected,
    required this.isFocused,
    required this.onDuplicate,
    required this.onToggleLocked,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    this.onEdit,
    this.onFullscreen,
    required this.onSettings,
    required this.onDelete,
    required this.onRename,
    this.leadingIcon,
    this.pluginActions = const [],
    this.remoteLockActor,
    super.key,
  });

  final BoardPanelInstance panel;
  final bool isSelected;
  final bool isFocused;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleLocked;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback? onEdit;
  final VoidCallback? onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onDelete;
  final void Function(String title) onRename;
  final Widget? leadingIcon;
  final List<Widget> pluginActions;

  /// Non-null when another remote actor holds the edit lock for this panel.
  final String? remoteLockActor;

  @override
  State<UnifiedPanelHeader> createState() => _UnifiedPanelHeaderState();
}

class _UnifiedPanelHeaderState extends State<UnifiedPanelHeader> {
  bool _editing = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.panel.title);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _controller.text = widget.panel.title;
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _commitRename() {
    final newTitle = _controller.text.trim();
    if (newTitle.isNotEmpty && newTitle != widget.panel.title) {
      widget.onRename(newTitle);
    }
    setState(() => _editing = false);
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panel = widget.panel;
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final accent = panel.color ?? plugin?.accentColor;
    final headerColor = widget.isSelected || widget.isFocused
        ? colors.surfaceElevated
        : colors.surface;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: headerColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actionsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.remoteLockActor != null)
                HeaderIconButton(
                  icon: Icons.lock_outline,
                  tooltip: 'Editing by ${widget.remoteLockActor}',
                  onPressed: () {},
                )
              else ...[
                HeaderIconButton(
                  icon: Icons.copy,
                  tooltip: 'Duplicate panel',
                  onPressed: widget.onDuplicate,
                ),
                HeaderIconButton(
                  icon: Icons.format_color_fill,
                  tooltip: 'Panel color',
                  onPressed: widget.onEditColor,
                  swatch: accent == Colors.transparent ? null : accent,
                ),
                if (widget.onEdit != null)
                  HeaderIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit content',
                    onPressed: widget.onEdit!,
                  ),
              ],
              ...widget.pluginActions,
              PanelOverflowMenu(
                onToggleLocked: widget.onToggleLocked,
                locked: panel.locked,
                onBringToFront: widget.onBringToFront,
                onSendToBack: widget.onSendToBack,
                onFullscreen: widget.onFullscreen,
                onSettings: widget.onSettings,
                onDelete: widget.onDelete,
              ),
              HeaderIconButton(
                icon: Icons.close,
                tooltip: 'Remove panel',
                onPressed: widget.onDelete,
              ),
            ],
          );
          // Rough natural width of the actions row: each action is a 28x28
          // HeaderIconButton. Used to decide between a fixed (right-aligned)
          // row and a scrollable flexible one for very narrow panels.
          final actionCount =
              (widget.remoteLockActor != null ? 1 : 2) +
              (widget.onEdit != null && widget.remoteLockActor == null
                  ? 1
                  : 0) +
              widget.pluginActions.length +
              2; // overflow menu + close
          final estimatedActionsWidth = actionCount * 28.0;
          // Chrome before the title: drag handle + icon + spacings + edit
          // button; keep at least ~120px for the title text.
          const minTitleChromeWidth = 28.0 + 8 + 16 + 8 + 28 + 120;
          final actionsFit =
              constraints.maxWidth >=
              estimatedActionsWidth + minTitleChromeWidth;
          return Row(
            children: [
              HeaderIconButton(
                icon: Icons.drag_indicator,
                tooltip: panel.locked ? 'Panel is locked' : 'Move panel',
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              widget.leadingIcon ?? _PanelIcon(plugin: plugin),
              const SizedBox(width: 8),
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _commitRename(),
                        onTapOutside: (_) => _commitRename(),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              panel.title,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (_editing)
                HeaderIconButton(
                  icon: Icons.check,
                  tooltip: 'Confirm rename',
                  onPressed: _commitRename,
                )
              else
                HeaderIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Rename panel',
                  onPressed: _startEditing,
                ),
              if (actionsFit)
                actionsRow
              else
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    child: actionsRow,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PanelIcon extends StatelessWidget {
  const _PanelIcon({this.plugin});

  final BoardPanelPlugin? plugin;

  @override
  Widget build(BuildContext context) {
    final svgIcon = plugin?.buildIconWidget(context, size: 16);
    if (svgIcon != null) return svgIcon;
    return Icon(
      plugin?.icon ?? Icons.dashboard_customize_outlined,
      size: 16,
      color: context.appColors.textSecondary,
    );
  }
}
