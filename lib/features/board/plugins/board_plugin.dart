import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Read-only context passed to a plugin when rendering its panel content.
class BoardPanelRenderContext {
  const BoardPanelRenderContext({
    required this.isSelected,
    required this.onFocus,
    required this.onDelete,
    required this.onUpdateState,
    required this.onShowEditor,
    this.onCreateLinkedPanel,
    this.onResize,
    this.onFindPanelByGroup,
    this.onRevealSessionInPanel,
    this.onFocusPanelById,
  });

  final bool isSelected;
  final VoidCallback onFocus;
  final VoidCallback onDelete;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final VoidCallback onShowEditor;

  /// Resize the panel to exact width × height.
  final void Function(double width, double height)? onResize;

  /// Creates a new panel linked to the current one and returns its id.
  /// [typeId] is the plugin type, [state] is the initial state, [title] is the
  /// panel title.
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )? onCreateLinkedPanel;

  /// Finds an existing panel by [typeId] and run [group] (if available).
  final String? Function(String typeId, String group)? onFindPanelByGroup;

  /// Reveals a detached run [sessionId] in target [panelId].
  final Future<void> Function(String panelId, String sessionId)?
      onRevealSessionInPanel;

  /// Focuses an existing panel by ID.
  final Future<void> Function(String panelId)? onFocusPanelById;
}

/// Abstract base class for board panel plugins.
///
/// Implement this to create a new panel type. Register it with
/// [BoardPluginRegistry.instance.register] — typically in [main] or an app
/// initialiser — to make it available in the board catalog.
///
/// Example:
/// ```dart
/// class MyCustomPlugin extends BoardPanelPlugin {
///   @override String get typeId => 'acme.my_custom';
///   @override String get displayName => 'My Custom Panel';
///   @override IconData get icon => Icons.star_outlined;
///   @override Widget buildContent(context, panel, ctx) => Text('hello');
/// }
/// ```
abstract class BoardPanelPlugin {
  const BoardPanelPlugin();

  /// Globally unique type identifier, e.g. `'board.note.markdown'`.
  String get typeId;

  /// Short human-readable name shown in the catalog and tooltips.
  String get displayName;

  /// Icon used in the catalog and the panel header.
  IconData get icon;

  /// Optional widget icon (e.g. SVG) to use instead of [icon] in headers.
  /// When non-null, this takes precedence over [icon].
  Widget? buildIconWidget(BuildContext context, {double size = 16}) => null;

  /// Accent color used to tint the panel header when no user color is set.
  /// Defaults to transparent (theme surface).
  Color get accentColor => Colors.transparent;

  /// Default size when a new panel is placed on the board.
  Size get defaultSize => const Size(360, 220);

  /// Initial state map for a freshly created panel.
  Map<String, dynamic> get initialState => const {};

  /// Build the content widget rendered inside the panel body.
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  );

  /// Optionally open an editor (dialog / bottom-sheet / inline) for this panel.
  /// Return `true` if an edit was made so the caller can refresh state.
  /// Default: no-op (returns false). Override when the panel has editable content.
  Future<bool> showEditor(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onSave,
  ) async {
    return false;
  }

  /// Whether this plugin provides a custom editor accessible from the panel header.
  bool get hasEditor => false;
}
