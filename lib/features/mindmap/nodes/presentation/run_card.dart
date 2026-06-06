import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/ui/components/buttons/small_action_button.dart';

/// Presentation run card — identical visuals to macOS RunNode.
class RunCard extends StatelessWidget {
  const RunCard({
    super.key,
    required this.props,
    this.onStart,
    this.onStop,
    this.onRestart,
    this.onCopy,
  });
  final RunCardProps props;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRunning = props.isRunning;
    final statusColor = switch (props.status) {
      'running' => colors.accentGreen,
      'failed' => colors.accentRed,
      _ => colors.textSecondary,
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color:
              isRunning
                  ? colors.accentGreen.withAlpha(85)
                  : colors.border.withAlpha(85),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors.background.withAlpha(128),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isRunning
                      ? colors.accentGreen.withAlpha(15)
                      : colors.surfaceHighlight.withAlpha(15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 12,
                  color: colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    props.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SmallActionButton(
                  icon: Icons.copy_all_rounded,
                  tooltip: 'Copy all logs',
                  color: colors.primaryLight,
                  onTap:
                      onCopy ??
                      () {
                        final text = props.lines.map((l) => l.text).join('\n');
                        copyToClipboard(text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Logs copied to clipboard'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            width: 220,
                          ),
                        );
                      },
                ),
                const SizedBox(width: 4),
                if (isRunning)
                  SmallActionButton(
                    icon: Icons.stop_rounded,
                    tooltip: 'Stop',
                    color: colors.accentRed,
                    onTap: onStop,
                  )
                else
                  SmallActionButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: 'Start',
                    color: colors.accentGreen,
                    onTap: onStart,
                  ),
                const SizedBox(width: 4),
                SmallActionButton(
                  icon: Icons.refresh,
                  tooltip: 'Restart',
                  color: colors.accentBlue,
                  onTap: onRestart,
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: SelectionArea(
                child: Container(
                  color: colors.terminalBackground,
                  child:
                      props.lines.isEmpty
                          ? Center(
                            child: Text(
                            'No output',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textMuted,
                            ),
                          ),
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: props.lines.length,
                          itemBuilder: (context, i) {
                            final line = props.lines[i];
                            return Text(
                              line.text,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color:
                                    line.isError
                                        ? colors.accentRed
                                        : colors.terminalText,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


