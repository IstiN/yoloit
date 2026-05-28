import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation workspace card — identical visuals to macOS WorkspaceNode.
class WorkspaceCard extends StatelessWidget {
  const WorkspaceCard({
    super.key,
    required this.props,
    this.onAddFolder,
    this.onCreateSession,
    this.onColorDotTap,
    this.onRemoveFolder,
  });
  final WorkspaceCardProps props;
  final VoidCallback? onAddFolder;
  final VoidCallback? onCreateSession;
  final VoidCallback? onColorDotTap;

  /// Called with the full folder path when the user removes a folder from context.
  final void Function(String path)? onRemoveFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = props.color ?? colors.accentBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colors.surfaceElevated, color, 0.08)!,
            Color.lerp(colors.surface, color, 0.04)!,
          ],
        ),
        border: Border.all(color: color.withAlpha(128), width: 1.5),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(20),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: colors.background.withAlpha(128),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              MouseRegion(
                cursor:
                    onColorDotTap != null
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                child: GestureDetector(
                  onTap: onColorDotTap,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(color: color.withAlpha(160), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  props.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (props.paths.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...props.paths.map(
              (path) => _FolderRow(
                path: path,
                onRemove:
                    onRemoveFolder != null ? () => onRemoveFolder!(path) : null,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _WsActionBtn(
                icon: Icons.create_new_folder_outlined,
                label: 'Folder',
                onTap: onAddFolder,
              ),
              const SizedBox(width: 6),
              _WsActionBtn(
                icon: Icons.terminal,
                label: 'Session',
                onTap: onCreateSession,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({required this.path, this.onRemove});
  final String path;
  final VoidCallback? onRemove;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 10, color: colors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                p.basename(widget.path),
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_hovered && widget.onRemove != null)
              GestureDetector(
                onTap: widget.onRemove,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 10, color: colors.accentRed),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WsActionBtn extends StatefulWidget {
  const _WsActionBtn({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_WsActionBtn> createState() => _WsActionBtnState();
}

class _WsActionBtnState extends State<_WsActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? colors.tabActiveBg : colors.surfaceHighlight,
            border: Border.all(
              color: _hovered ? colors.accentBlue : colors.border,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 11,
                color: _hovered ? colors.accentBlue : colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _hovered ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
