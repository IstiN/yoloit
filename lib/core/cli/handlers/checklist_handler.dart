import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Checklist panels (`board.checklist`).
class ChecklistCliHandler extends PanelCliHandler {
  const ChecklistCliHandler();

  @override
  String get typeId => 'board.checklist';

  @override
  List<String> get supportedActions => [
    'items',
    'add',
    'check',
    'uncheck',
    'remove',
    'rename',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'items': _items(panel)};
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
        final items = _items(panel);
        items.add({
          'id': 'item-${DateTime.now().millisecondsSinceEpoch}',
          'text': text,
          'done': false,
        });
        return CliActionResult(
          message: 'Item added',
          stateUpdate: {'items': items},
        );
      case 'check':
        return _setChecked(panel, args, true);
      case 'uncheck':
        return _setChecked(panel, args, false);
      case 'remove':
        final index = _indexArg(args);
        if (index == null) {
          return const CliActionResult(ok: false, message: 'Missing "index"');
        }
        final items = _items(panel);
        if (index < 0 || index >= items.length) {
          return const CliActionResult(
            ok: false,
            message: 'Index out of range',
          );
        }
        items.removeAt(index);
        return CliActionResult(
          message: 'Item removed',
          stateUpdate: {'items': items},
        );
      case 'rename':
        final index = _indexArg(args);
        final text = args['text'] as String?;
        if (index == null || text == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "index" and "text"',
          );
        }
        final items = _items(panel);
        if (index < 0 || index >= items.length) {
          return const CliActionResult(
            ok: false,
            message: 'Index out of range',
          );
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

  CliActionResult _setChecked(
    BoardPanelInstance panel,
    Map<String, dynamic> args,
    bool checked,
  ) {
    final items = _items(panel);
    final index =
        _indexArg(args) ??
        _indexById(items, args['id']?.toString()) ??
        _indexByText(items, _textArg(args));
    if (index == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing "index", "id", or "text"',
      );
    }
    if (index < 0 || index >= items.length) {
      return const CliActionResult(ok: false, message: 'Index out of range');
    }
    items[index] = {...items[index], 'done': checked};
    return CliActionResult(
      message: checked ? 'Item checked' : 'Item unchecked',
      stateUpdate: {'items': items},
    );
  }

  List<Map<String, dynamic>> _items(BoardPanelInstance panel) {
    final raw = panel.state['items'];
    if (raw is! List) return [];
    return [
      for (var i = 0; i < raw.length; i++)
        if (raw[i] is Map)
          {
            ...Map<String, dynamic>.from(raw[i] as Map),
            'id': (raw[i] as Map)['id']?.toString() ?? 'item-$i',
            'text': (raw[i] as Map)['text']?.toString() ?? '',
            'done':
                (raw[i] as Map)['done'] == true ||
                (raw[i] as Map)['checked'] == true,
          },
    ];
  }

  int? _indexArg(Map<String, dynamic> args) {
    final value = args['index'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _indexById(List<Map<String, dynamic>> items, String? id) {
    if (id == null || id.isEmpty) return null;
    final index = items.indexWhere((item) => item['id'] == id);
    return index < 0 ? null : index;
  }

  String? _textArg(Map<String, dynamic> args) {
    final direct = args['text']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final aliases = ['item', 'name', 'title'];
    for (final key in aliases) {
      final value = args[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int? _indexByText(List<Map<String, dynamic>> items, String? text) {
    if (text == null || text.isEmpty) return null;
    final needle = text.trim().toLowerCase();
    final exact = items.indexWhere(
      (item) => (item['text']?.toString().trim().toLowerCase() ?? '') == needle,
    );
    return exact < 0 ? null : exact;
  }
}
