import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Web stub for the audio recorder panel.
///
/// Browsers cannot capture system audio or use the native media backend, so the
/// panel renders a short explanatory placeholder.
Widget buildAudioRecorderContent(
  BoardPanelInstance panel,
  BoardPanelRenderContext renderContext,
) =>
    const _AudioRecorderUnsupported();

class _AudioRecorderUnsupported extends StatelessWidget {
  const _AudioRecorderUnsupported();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_rounded, size: 36, color: colors.textMuted),
            const SizedBox(height: 10),
            Text(
              'Audio Recorder is available in YoLoIT for macOS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
