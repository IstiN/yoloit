import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_content.dart';

/// Custom JS widget panel — web implementation.
class CustomWidgetPlugin extends CustomWidgetPluginBase {
  const CustomWidgetPlugin();

  static const String kTypeId = CustomWidgetPluginBase.kTypeId;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return CustomWidgetContent(panel: panel, renderContext: renderContext);
  }

  @override
  List<Widget> buildHeaderActions(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onUpdateState, {
    void Function(double w, double h)? onResize,
    VoidCallback? onEditColor,
  }) {
    return [
      if (onResize != null) QuickSizeButton(onResize: onResize),
      EnvGearButton(
        panel: panel,
        onUpdate: (selectedGroups, customVars) {
          onUpdateState({
            ...panel.state,
            '_selectedEnvGroups': selectedGroups,
            '_customEnvVars': customVars,
          });
        },
      ),
    ];
  }
}
