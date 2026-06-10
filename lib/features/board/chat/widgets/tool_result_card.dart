import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/widgets/chat_tool_status_badge.dart';

class ToolResultCard extends StatefulWidget {
  const ToolResultCard({
    required this.toolName,
    required this.toolCallId,
    required this.content,
    this.success,
    this.onSendToPanel,
    this.onOpenAgentPanel,
  });
  final String toolName;
  final String toolCallId;
  final String content;
  final bool? success;
  final VoidCallback? onSendToPanel;

  /// If set, shows a "View Agent Log →" button that opens the agent's board panel.
  final VoidCallback? onOpenAgentPanel;

  @override
  State<ToolResultCard> createState() => ToolResultCardState();
}

class ToolResultCardState extends State<ToolResultCard> {
  bool _expanded = false;

  void _copyResult() {
    copyToClipboard(widget.content);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tool result copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _openFullView() {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 900,
              height: 640,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.toolName} • Full view',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          tooltip: 'Copy',
                          onPressed: _copyResult,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        widget.content,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = ToolExecutionStatus.from(
      colors,
      success: widget.success,
      content: widget.content,
    );
    final previewText = toolResultPreview(widget.content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.border.withAlpha(100),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: status.tint.withAlpha(18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(status.icon, size: 14, color: status.tint),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.surface.withAlpha(180),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border.withAlpha(120)),
                    ),
                    child: Icon(
                      Icons.build_outlined,
                      size: 12,
                      color:
                          Theme.of(context).textTheme.bodyMedium?.color ??
                          Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.toolName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChatToolStatusBadge(status: status),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Copy',
                    child: InkWell(
                      onTap: _copyResult,
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 14,
                        color:
                            context.appColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Full view',
                    child: InkWell(
                      onTap: _openFullView,
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 14,
                        color:
                            context.appColors.textMuted,
                      ),
                    ),
                  ),
                  if (widget.onSendToPanel != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Send to panel',
                      child: InkWell(
                        onTap: widget.onSendToPanel,
                        child: Icon(
                          Icons.note_add_outlined,
                          size: 14,
                          color:
                              context.appColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                  if (widget.onOpenAgentPanel != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'View agent log',
                      child: InkWell(
                        onTap: widget.onOpenAgentPanel,
                        child: Icon(
                          Icons.smart_toy_outlined,
                          size: 14,
                          color: colors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color:
                        context.appColors.textMuted,
                  ),
                ],
              ),
              if (previewText != null && !_expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 28, right: 4),
                  child: Text(
                    previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color:
                          context.appColors.textMuted,
                    ),
                  ),
                ),
              if (_expanded && widget.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color.lerp(colors.surface, status.tint, 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border.withAlpha(110)),
                    ),
                    child: SelectableText(
                      widget.content,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color:
                            Theme.of(context).textTheme.bodyMedium?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
