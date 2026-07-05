import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/panel_editor_dialog_mixin.dart';

/// Shared metadata for the declarative JSON UI panel plugin.
abstract class UiViewPluginBase extends BoardPanelPluginBase
    with PanelEditorDialogMixin {
  const UiViewPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'UI View',
        icon: Icons.view_quilt_outlined,
        defaultSize: const Size(420, 320),
        initialState: const {'tree': _defaultTree},
        hasEditor: true,
        contentPadding: const EdgeInsets.all(8),
        requiredCapabilities: const {PlatformCapability.processes},
      );

  static const String kTypeId = 'board.ui';

  static const Map<String, dynamic> _defaultTree = <String, dynamic>{
    'type': 'column',
    'mainAxisAlignment': 'center',
    'crossAxisAlignment': 'center',
    'mainAxisSize': 'min',
    'children': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'text',
        'data': 'UI View',
        'style': <String, dynamic>{
          'fontSize': 22,
          'fontWeight': 'w700',
          'textAlign': 'center',
        },
      },
      <String, dynamic>{'type': 'sizedBox', 'height': 8},
      <String, dynamic>{
        'type': 'text',
        'data': 'Empty panel',
        'style': <String, dynamic>{
          'fontSize': 12,
          'color': '#94a3b8',
          'textAlign': 'center',
        },
      },
    ],
  };

  static Map<String, dynamic> defaultTree() => _defaultTree;

  static Map<String, dynamic>? treeFromState(Map<String, dynamic> state) {
    final raw = state['tree'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  @override
  Color get accentColor => const Color(0xFF7C3AED);

  @override
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel);
}
