import 'dart:typed_data';
import 'dart:ui';

import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/services/board_operation_applier.dart';
import 'package:yoloit/features/templates/data/template_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Generates a PNG preview of a [BoardTemplate] by applying its operations to
/// a transient [BoardDocument] and rendering it offscreen.
///
/// The generated board is never persisted to disk or SharedPreferences.
class TemplatePreviewGenerator {
  TemplatePreviewGenerator({
    BoardTemplateService? templateService,
  }) : templateService = templateService ?? BoardTemplateService.instance;

  final BoardTemplateService templateService;

  /// Renders a thumbnail for [template] using its default parameter values.
  ///
  /// Returns `null` if the template has no visible panels or rendering fails.
  /// Pass [cancelToken] to abort a stale render when the user switches
  /// templates quickly.
  Future<Uint8List?> generate(
    BoardTemplate template, {
    Size size = const Size(480, 320),
    double pixelRatio = 1.0,
    CancelToken? cancelToken,
  }) async {
    final values = templateService.buildEffectiveParameters(template, const {});
    final operations = templateService.buildOperations(template, values);

    final board = const BoardOperationApplier().buildDocument(
      BoardDocument(
        id: 'template-preview-${template.id}',
        name: template.name,
        viewport: const BoardViewport(),
      ),
      operations,
    );

    final visiblePanels = board.panels.where((p) => !p.hidden).toList();
    if (visiblePanels.isEmpty) return null;

    return BoardOffscreenRenderer.instance.renderBoard(
      board,
      size: size,
      pixelRatio: pixelRatio,
      cancelToken: cancelToken,
      useViewport: false,
    );
  }
}
