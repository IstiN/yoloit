import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation workspace card — identical visuals to macOS WorkspaceNode.
class WorkspaceCard extends StatelessWidget {
  const WorkspaceCard({
    super.key,
    required this.props,
    this.onAddFolder,
    this.onCreateSession,
    this.onRemoveFolder,
  });
  final WorkspaceCardProps props;
  final VoidCallback? onAddFolder;
  final VoidCallback? onCreateSession;
  /// Called with the full folder path when the user removes a folder from context.
  final void Function(String path)? onRemoveFolder;

  static const _borderColor = Color(0x8060A5FA);
  static const _bgGrad = [Color(0xFF181E2E), Color(0xFF141826)];

  @override
  Widget build(BuildContext context) {
    final color = props.color ?? const Color(0xFF60A5FA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _bgGrad,
        ),
        border: Border.all(color: _borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1460A5FA), blurRadius: 24, offset: Offset(0, 4)),
          BoxShadow(
              color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withAlpha(160), blurRadius: 8)
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  props.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8E8FF)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (props.paths.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...props.paths.map((path) => _FolderRow(
                  path: path,
                  onRemove: onRemoveFolder != null ? () => onRemoveFolder!(path) : null,
                )),
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
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 10, color: Color(0xFF6B7898)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                p.basename(widget.path),
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7898)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_hovered && widget.onRemove != null)
              GestureDetector(
                onTap: widget.onRemove,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 10, color: Color(0xFFEF4444)),
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
            color: _hovered
                ? const Color(0xFF2A3A66)
                : const Color(0xFF1A1E2A),
            border: Border.all(
                color: _hovered
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2A3040)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 11,
                  color: _hovered
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF8A93B0)),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _hovered
                      ? const Color(0xFFE8E8FF)
                      : const Color(0xFF9AA3BF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
