import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/history/board_panel_history_adapter.dart';
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
    this.onFindPanelById,
    this.remoteInfo,
    this.isHeadlessPreview = false,
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
  )?
  onCreateLinkedPanel;

  /// Finds an existing panel by [typeId] and run [group] (if available).
  final String? Function(String typeId, String group)? onFindPanelByGroup;

  /// Reveals a detached run [sessionId] in target [panelId].
  final Future<void> Function(String panelId, String sessionId)?
  onRevealSessionInPanel;

  /// Focuses an existing panel by ID.
  final Future<void> Function(String panelId)? onFocusPanelById;

  /// Looks up an existing panel by ID. Used by panels that reference other
  /// panels, e.g. a chart reading data from a table panel.
  final BoardPanelInstance? Function(String panelId)? onFindPanelById;

  /// Remote board connection metadata. Null means the panel belongs to a local
  /// board and filesystem actions should use the local machine.
  final RemoteBoardInfo? remoteInfo;

  /// True when a panel is rendered by the offscreen board preview/screenshot
  /// pipeline instead of the interactive board UI.
  final bool isHeadlessPreview;
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

  /// Plugin-owned state history adapter.
  ///
  /// All panel state must pass through this contract before being written into
  /// board history. Override for panels with volatile fields or nested entities
  /// that need finer-grained restore.
  BoardPanelHistoryAdapter get historyAdapter =>
      const JsonBoardPanelHistoryAdapter();

  /// Whether this plugin should be shown in the generic Add Panel catalog.
  bool get showInCatalog => true;

  /// Whether the board should draw the standard rounded panel background,
  /// border, and shadow around this plugin.
  bool get usePanelChrome => true;

  /// Whether the board should draw the standard title/header row.
  bool get showHeader => true;

  /// Padding applied around the plugin content inside the panel body.
  ///
  /// Return [EdgeInsets.zero] when the plugin draws its own chrome (e.g. a chat
  /// input bar that should sit flush against the panel edges).
  EdgeInsets get contentPadding => const EdgeInsets.all(12);

  /// Whether this plugin can be safely rendered in a headless offscreen context
  /// (no GPU, no platform views, no native video decoders).
  ///
  /// Override to `false` for plugins that call native code in their widget
  /// constructors or [State.initState] — e.g. media players (MPV), WebView,
  /// or terminal PTY. The offscreen renderer will show a grey placeholder
  /// instead of calling [buildContent] for these plugins.
  bool get supportsHeadlessRender => true;

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

  /// Convenience helper for plugins that only need a simple `showDialog`
  /// followed by merging the result into panel state.
  ///
  /// Replaces the duplicated `showEditor` boilerplate in [ShapePlugin],
  /// [StickyNotePlugin], and similar editors.
  Future<bool> showPanelEditorDialog(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onSave,
    WidgetBuilder builder,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: builder,
    );
    if (result == null) return false;
    onSave({...panel.state, ...result});
    return true;
  }

  /// Whether this plugin provides a custom editor accessible from the panel header.
  bool get hasEditor => false;

  /// Optional widgets to inject into the panel header row (before the overflow
  /// menu and close button). Use for plugin-specific header actions (e.g. env
  /// variable gear icon).
  List<Widget> buildHeaderActions(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onUpdateState, {
    void Function(double w, double h)? onResize,
    VoidCallback? onEditColor,
  }) => const [];

  /// Optional content-level toolbar rendered below the header.
  ///
  /// Lets plugins expose their primary actions (add row, chart type, terminal
  /// env groups, etc.) in the unified chrome instead of embedding them inside
  /// [buildContent]. Return `null` or an empty list to hide the toolbar.
  List<Widget>? buildContentToolbar(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) => null;
}
