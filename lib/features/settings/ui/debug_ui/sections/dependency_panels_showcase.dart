import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/chart_plugin.dart';
import 'package:yoloit/features/chart/model/chart_models.dart';
import 'package:yoloit/features/chart/ui/chart_panel_content.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

/// Live samples for panels backed by major-version dependencies (fl_chart,
/// media_kit_video). Open Settings → Debug UI → Dependency Panels to verify
/// upgrades manually.
class DependencyPanelsShowcase extends StatefulWidget {
  const DependencyPanelsShowcase({super.key});

  @override
  State<DependencyPanelsShowcase> createState() =>
      _DependencyPanelsShowcaseState();
}

class _DependencyPanelsShowcaseState extends State<DependencyPanelsShowcase> {
  static const _sampleVideoUrl =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';

  late final Player _player;
  late final VideoController _videoController;
  var _videoReady = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _startSampleVideo();
  }

  Future<void> _startSampleVideo() async {
    try {
      await _player.open(Media(_sampleVideoUrl), play: false);
      if (mounted) setState(() => _videoReady = true);
    } catch (e) {
      if (mounted) setState(() => _videoError = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  BoardPanelRenderContext get _noopContext => BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

  BoardPanelInstance _chartPanel(ChartType type) => BoardPanelInstance(
        id: 'debug-chart-${type.name}',
        type: ChartPlugin.kTypeId,
        title: 'Chart (${type.name})',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 260),
        state: {
          ...const ChartPlugin().initialState,
          'type': type.name,
          'animated': false,
        },
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShowcaseScaffold(
      children: [
        const SectionTitle('Major dependency panels (manual QA)'),
        const SizedBox(height: 6),
        Text(
          'fl_chart ^1.2 • media_kit_video ^2.0 — use this page after dependency bumps.',
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 20),
        const SectionTitle('Chart panel — all types (fl_chart)'),
        const SizedBox(height: 8),
        for (final type in ChartType.values) ...[
          Text(
            type.name.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
              color: colors.surface,
            ),
            child: SizedBox(
              height: 220,
              child: MaterialApp(
                theme: AppThemePreset.neonPurple.theme,
                home: ChartPanelContent(
                  panel: _chartPanel(type),
                  renderContext: _noopContext,
                ),
              ),
            ),
          ),
        ],
        const SectionTitle('Playlist / file preview — video (media_kit_video)'),
        const SizedBox(height: 8),
        Text(
          'Board panels: board.playlist (audio+video queue) and board.file_preview '
          '(video files). Sample stream below uses the same Video widget stack.',
          style: TextStyle(color: colors.textMuted, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 10),
        Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
            color: colors.surfaceElevated,
          ),
          clipBehavior: Clip.antiAlias,
          child: _videoError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Video sample failed: $_videoError',
                      style: TextStyle(color: colors.accentRed, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _videoReady
                  ? Video(
                      controller: _videoController,
                      controls: AdaptiveVideoControls,
                    )
                  : Center(
                      child: Text(
                        'Loading sample video…',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                    ),
        ),
        const SizedBox(height: 8),
        Text(
          'On a board: add Playlist panel → paste URL in track path, or drop a local '
          '.mp4/.mp3. File Preview panel opens video files from disk.',
          style: TextStyle(color: colors.textMuted, fontSize: 10, height: 1.5),
        ),
      ],
    );
  }
}
