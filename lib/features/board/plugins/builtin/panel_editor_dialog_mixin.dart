import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Mixin for [PanelPlugin]s whose editor is a simple dialog built via
/// [showPanelEditorDialog].
mixin PanelEditorDialogMixin on PanelPlugin {
  /// Builds the editor dialog widget for this panel.
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel);

  @override
  Future<bool> showEditor(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onSave,
  ) => showPanelEditorDialog(
    context,
    panel,
    onSave,
    (ctx) => buildEditorDialog(ctx, panel),
  );
}
