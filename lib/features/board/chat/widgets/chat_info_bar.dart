import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/provider_icon.dart';

/// Info bar shown at the top of a chat panel.
class ChatInfoBar extends StatelessWidget {
  const ChatInfoBar({
    required this.workingDir,
    required this.provider,
    required this.model,
    required this.autopilot,
    required this.reasoningEffort,
    required this.totalOutputTokens,
    required this.isProcessing,
    required this.enabledLocalToolCount,
    required this.totalLocalToolCount,
    required this.onAutopilotToggle,
    required this.onCycleReasoningEffort,
    required this.onCopySession,
    required this.onShowHistory,
    required this.shortPath,
    super.key,
  });

  final String workingDir;
  final String provider;
  final String model;
  final bool autopilot;
  final String? reasoningEffort;
  final int totalOutputTokens;
  final bool isProcessing;
  final int enabledLocalToolCount;
  final int totalLocalToolCount;
  final VoidCallback onAutopilotToggle;
  final VoidCallback onCycleReasoningEffort;
  final VoidCallback onCopySession;
  final VoidCallback onShowHistory;
  final String Function(String) shortPath;

  String _reasoningLabel() {
    return switch (reasoningEffort) {
      'low' => 'Effort: low',
      'medium' => 'Effort: med',
      'high' => 'Effort: high',
      'xhigh' => 'Effort: xhigh',
      _ => 'Effort',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = context.appColors.textMuted.withAlpha(153);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 11, color: muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              shortPath(workingDir),
              style: TextStyle(fontSize: 10, color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ChatProviderIcon(provider: provider, size: 14, color: muted),
          if (provider == 'local') ...[
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Local tools: $enabledLocalToolCount/$totalLocalToolCount enabled',
              child: Icon(Icons.construction, size: 12, color: muted),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAutopilotToggle,
            child: Tooltip(
              message: autopilot ? 'Autopilot ON' : 'Autopilot OFF',
              child: Icon(
                Icons.rocket_launch,
                size: 12,
                color: autopilot ? colors.statusActive : muted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onCycleReasoningEffort,
            child: Tooltip(
              message: 'Effort: ${reasoningEffort ?? 'default'}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      reasoningEffort != null
                          ? colors.statusWarning.withAlpha(32)
                          : colors.surfaceHighlight.withAlpha(21),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        reasoningEffort != null
                            ? colors.statusWarning.withAlpha(128)
                            : colors.border,
                    width: 0.6,
                  ),
                ),
                child: Text(
                  _reasoningLabel(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color:
                        reasoningEffort != null
                            ? colors.statusWarning
                            : muted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(model, style: TextStyle(fontSize: 9, color: muted)),
          if (totalOutputTokens > 0) ...[
            const SizedBox(width: 6),
            Text(
              '∑$totalOutputTokens',
              style: TextStyle(fontSize: 9, color: colors.primary),
            ),
          ],
          if (isProcessing)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2,
                  color: colors.statusActive,
                ),
              ),
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onCopySession,
            child: Tooltip(
              message: 'Copy session',
              child: Icon(Icons.copy_all_outlined, size: 13, color: muted),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onShowHistory,
            child: Icon(Icons.history, size: 13, color: muted),
          ),
        ],
      ),
    );
  }
}
