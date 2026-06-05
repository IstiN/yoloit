import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';

class LogRow extends StatelessWidget {
  const LogRow({
    super.key,
    required this.log,
    required this.onDelete,
    required this.onView,
  });

  final LogFile log;
  final VoidCallback onDelete;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color: context.appColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onView,
              child: Text(
                log.name,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text(
            log.sizeLabel,
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              Icons.close,
              size: 14,
              color: context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key, required this.log});
  final LogFile log;

  @override
  State<LogViewerDialog> createState() => LogViewerDialogState();
}

class LogViewerDialogState extends State<LogViewerDialog> {
  String? _content;

  @override
  void initState() {
    super.initState();
    LoggingService.instance.readLog(widget.log.path).then((c) {
      if (mounted) setState(() => _content = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.log.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  widget.log.sizeLabel,
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: context.appColors.textMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child:
                _content == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content!,
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodyMedium?.color ??
                              Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
