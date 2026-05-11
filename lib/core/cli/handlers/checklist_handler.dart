import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Checklist panels (`board.checklist`).
class ChecklistCliHandler extends PanelCliHandler {
  const ChecklistCliHandler();

  @override
  String get typeId => 'board.checklist';

  @override
  List<String> get supportedActions => ['items', 'add', 'check', 'uncheck', 'remove', 'rename'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'items': panel.state['items'] ?? []};
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'items':
        return CliActionResult(data: getContent(panel));
      case 'add':
        final text = args['text'] as String?;
        if (text == null) {
          return const CliActionResult(ok: false, message: 'Missing "text"');
        }
        final items = List<Map<String, dynamic>>.from(
          (panel.state['items'] as List<dynamic>?) ?? [],
        );
        items.add({'text': text, 'checked': false});
        return CliActionResult(
          message: 'Item added',
          stateUpdate: {'items': items},
        );
      case 'check':
        return _setChecked(panel, args, true);
      case 'uncheck':
        return _setChecked(panel, args, false);
      case 'remove':
        final index = args['index'] as int?;
        if (index == null) {
          return const CliActionResult(ok: false, message: 'Missing "index"');
        }
        final items = List<Map<String, dynamic>>.from(
          (panel.state['items'] as List<dynamic>?) ?? [],
        );
        if (index < 0 || index >= items.length) {
          return const CliActionResult(ok: false, message: 'Index out of range');
        }
        items.removeAt(index);
        return CliActionResult(
          message: 'Item removed',
          stateUpdate: {'items': items},
        );
      case 'rename':
        final index = args['index'] as int?;
        final text = args['text'] as String?;
        if (index == null || text == null) {
          return const CliActionResult(ok: false, message: 'Missing "index" and "text"');
        }
        final items = List<Map<String, dynamic>>.from(
          (panel.state['items'] as List<dynamic>?) ?? [],
        );
        if (index < 0 || index >= items.length) {
          return const CliActionResult(ok: false, message: 'Index out of range');
        }
        items[index] = {...items[index], 'text': text};
        return CliActionResult(
          message: 'Item renamed',
          stateUpdate: {'items': items},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  CliActionResult _setChecked(BoardPanelInstance panel, Map<String, dynamic> args, bool checked) {
    final index = args['index'] as int?;
    if (index == null) {
      return const CliActionResult(ok: false, message: 'Missing "index"');
    }
    final items = List<Map<String, dynamic>>.from(
      (panel.state['items'] as List<dynamic>?) ?? [],
    );
    if (index < 0 || index >= items.length) {
      return const CliActionResult(ok: false, message: 'Index out of range');
    }
    items[index] = {...items[index], 'checked': checked};
    return CliActionResult(
      message: checked ? 'Item checked' : 'Item unchecked',
      stateUpdate: {'items': items},
    );
  }
}
