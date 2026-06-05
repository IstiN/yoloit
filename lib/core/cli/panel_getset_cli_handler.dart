import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Mixin for panel CLI handlers that only need standard `get` and `set` actions.
///
/// Implementations must provide [settableKeys] (the state keys that can be
/// updated) and [settableName] (human-readable noun for error messages).
///
/// Used by [ShapeCliHandler], [StickyNoteCliHandler], and similar simple
/// panel handlers to eliminate the duplicated `get`/`set` switch-case
/// boilerplate.
mixin PanelGetSetCliHandler on PanelCliHandler {
  /// State keys that the `set` action is allowed to mutate.
  List<String> get settableKeys;

  /// Short human-readable name of the panel type (e.g. `'Shape'`,
  /// `'Sticky note'`). Used in result messages.
  String get settableName;

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'set':
        final update = <String, dynamic>{};
        for (final key in settableKeys) {
          if (args.containsKey(key)) update[key] = args[key];
        }
        if (update.isEmpty) {
          return CliActionResult(
            ok: false,
            message: 'Missing $settableName fields to update',
          );
        }
        return CliActionResult(
          message: '$settableName updated',
          stateUpdate: update,
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
