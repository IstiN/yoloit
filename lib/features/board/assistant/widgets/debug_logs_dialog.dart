import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/assistant/widgets/debug_session_list_view.dart';

class DebugLogsDialog extends StatelessWidget {
  const DebugLogsDialog({
    required this.sessions,
    required this.activeSession,
    required this.onSimulate,
    required this.onClear,
  });

  final List<Map<String, dynamic>> sessions;
  final Map<String, dynamic>? activeSession;
  final VoidCallback onSimulate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displaySessions =
        List<Map<String, dynamic>>.from(sessions).reversed.toList();
    if (activeSession != null &&
        !displaySessions.any((s) => s['id'] == activeSession!['id'])) {
      displaySessions.insert(0, activeSession!);
    }
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.bug_report_outlined, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('LLM Debug Logs')),
          Text(
            '${displaySessions.length} sessions',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
      content: SizedBox(
        width: 800,
        height: 660,
        child:
            displaySessions.isEmpty
                ? const Center(
                  child: Text(
                    'No LLM sessions yet.\nSend a message to see raw logs here.',
                    textAlign: TextAlign.center,
                  ),
                )
                : DebugSessionListView(
                  sessions: displaySessions,
                  colors: colors,
                ),
      ),
      actions: [
        TextButton(onPressed: onSimulate, child: const Text('Simulate')),
        TextButton(onPressed: onClear, child: const Text('Clear')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
