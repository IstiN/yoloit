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

/// Truncate [s] to [max] chars, adding an ellipsis when truncated.
String truncateText(String s, int max) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

/// Format stored panel messages for CLI output.
CliActionResult formatStoredMessages(
  Map<String, dynamic> args,
  BoardPanelInstance panel, {
  String key = 'messages',
}) {
  final msgs = panel.state[key] as List<dynamic>? ?? [];
  final limit = args['limit'] as int? ?? msgs.length;
  final filtered =
      msgs.length > limit ? msgs.sublist(msgs.length - limit) : msgs;
  return CliActionResult(data: {'total': msgs.length, 'messages': filtered});
}

/// Build a CLI-safe message map from raw panel state.
Map<String, dynamic> formatMessageItem(Map<String, dynamic> msg, int maxLen) => {
  'role': msg['role'] ?? 'unknown',
  'content': truncateText(msg['content'] as String? ?? '', maxLen),
};

/// Result of a CLI action execution.
class CliActionResult {
  const CliActionResult({
    this.ok = true,
    this.message,
    this.data,
    this.stateUpdate,
    this.additionalStateUpdates,
  });

  /// Whether the action succeeded.
  final bool ok;

  /// Human-readable result message.
  final String? message;

  /// Structured response data.
  final Map<String, dynamic>? data;

  /// If non-null, these key/values should be merged into the action target
  /// panel's state.
  final Map<String, dynamic>? stateUpdate;

  /// Optional state updates for other panels on the same board.
  ///
  /// Map keys are panel IDs; values are state patches to merge.
  final Map<String, Map<String, dynamic>>? additionalStateUpdates;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    if (!ok && message != null) 'error': message,
    if (ok && message != null) 'message': message,
    if (ok && data != null) 'data': data,
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
