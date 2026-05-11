import 'package:yoloit/features/board/model/board_models.dart';

/// Abstract base class for panel-specific CLI command handlers.
///
/// Each [BoardPanelPlugin] that supports CLI interaction should provide
/// a concrete implementation via [BoardPanelPlugin.cliHandler].
///
/// Handlers translate CLI actions into panel state mutations and return
/// structured data for the CLI client.
abstract class PanelCliHandler {
  const PanelCliHandler();

  /// Unique type identifier matching the plugin's [typeId].
  String get typeId;

  /// Returns the list of supported action names (e.g. `['send', 'messages']`).
  List<String> get supportedActions;

  /// Serialise the panel content/state for CLI output.
  ///
  /// This should return all user-visible content (messages, items, text, etc.)
  /// in a structured form suitable for JSON serialisation.
  Map<String, dynamic> getContent(BoardPanelInstance panel);

  /// Execute a panel-specific action.
  ///
  /// [action] is the verb (e.g. `'send'`, `'add-card'`).
  /// [args] is a map of action parameters from the CLI request.
  /// [panel] is the current panel instance.
  ///
  /// Returns a result map containing:
  /// - `ok: true/false`
  /// - Optional response data
  /// - Optional `stateUpdate` map to be merged into panel state.
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  );

  /// Returns a help map for all supported actions with their parameters.
  Map<String, CliActionHelp> get actionHelp => {};
}

/// Result of a CLI action execution.
class CliActionResult {
  const CliActionResult({
    this.ok = true,
    this.message,
    this.data,
    this.stateUpdate,
  });

  /// Whether the action succeeded.
  final bool ok;

  /// Human-readable result message.
  final String? message;

  /// Structured response data.
  final Map<String, dynamic>? data;

  /// If non-null, these key/values should be merged into the panel's state.
  final Map<String, dynamic>? stateUpdate;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    if (message != null) 'message': message,
    if (data != null) 'data': data,
  };
}

/// Describes one CLI action for help/documentation.
class CliActionHelp {
  const CliActionHelp({
    required this.description,
    this.params = const {},
    this.example,
  });

  final String description;
  final Map<String, String> params;
  final String? example;
}
