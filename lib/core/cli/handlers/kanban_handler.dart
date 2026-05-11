import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Kanban panels (`board.kanban`).
class KanbanCliHandler extends PanelCliHandler {
  const KanbanCliHandler();

  @override
  String get typeId => 'board.kanban';

  @override
  List<String> get supportedActions => [
    'columns',
    'cards',
    'add-column',
    'rename-column',
    'remove-column',
    'add-card',
    'move-card',
    'remove-card',
    'update-card',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final columns = _columns(panel);
    final cards = _cards(panel);
    return {
      'columns': columns.map((c) {
        final colCards = cards.where((card) =>
          card['columnId'] == c['id']).toList();
        return {
          ...c,
          'cards': colCards,
        };
      }).toList(),
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'columns':
        return CliActionResult(data: {'columns': _columns(panel)});
      case 'cards':
        return CliActionResult(data: getContent(panel));
      case 'add-column':
        final name = args['name'] as String?;
        if (name == null) {
          return const CliActionResult(ok: false, message: 'Missing "name"');
        }
        final columns = List<Map<String, dynamic>>.from(_columns(panel));
        final id = 'col-${DateTime.now().millisecondsSinceEpoch}';
        columns.add({'id': id, 'title': name});
        return CliActionResult(
          message: 'Column "$name" added',
          stateUpdate: {'columns': columns},
          data: {'columnId': id},
        );
      case 'rename-column':
        final colId = args['columnId'] as String? ?? args['column'] as String?;
        final name = args['name'] as String?;
        if (colId == null || name == null) {
          return const CliActionResult(ok: false, message: 'Missing "columnId" and "name"');
        }
        final columns = List<Map<String, dynamic>>.from(_columns(panel));
        final idx = _findColumnIndex(columns, colId);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Column not found: $colId');
        }
        columns[idx] = {...columns[idx], 'title': name};
        return CliActionResult(
          message: 'Column renamed to "$name"',
          stateUpdate: {'columns': columns},
        );
      case 'remove-column':
        final colId = args['columnId'] as String? ?? args['column'] as String?;
        if (colId == null) {
          return const CliActionResult(ok: false, message: 'Missing "columnId"');
        }
        final columns = List<Map<String, dynamic>>.from(_columns(panel));
        final resolvedId = _resolveColumnId(columns, colId);
        if (resolvedId == null) {
          return CliActionResult(ok: false, message: 'Column not found: $colId');
        }
        columns.removeWhere((c) => c['id'] == resolvedId);
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        cards.removeWhere((c) => c['columnId'] == resolvedId);
        return CliActionResult(
          message: 'Column removed',
          stateUpdate: {'columns': columns, 'cards': cards},
        );
      case 'add-card':
        final colId = args['columnId'] as String? ?? args['column'] as String?;
        final title = args['title'] as String?;
        if (colId == null || title == null) {
          return const CliActionResult(ok: false, message: 'Missing "columnId" and "title"');
        }
        final columns = _columns(panel);
        final resolvedColId = _resolveColumnId(columns, colId);
        if (resolvedColId == null) {
          return CliActionResult(ok: false, message: 'Column not found: $colId');
        }
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        final cardId = 'card-${DateTime.now().millisecondsSinceEpoch}';
        cards.add({
          'id': cardId,
          'columnId': resolvedColId,
          'title': title,
          if (args['description'] != null) 'description': args['description'],
          if (args['color'] != null) 'color': args['color'],
        });
        return CliActionResult(
          message: 'Card "$title" added',
          stateUpdate: {'cards': cards},
          data: {'cardId': cardId},
        );
      case 'move-card':
        final cardId = args['cardId'] as String?;
        final toCol = args['to'] as String? ?? args['columnId'] as String?;
        if (cardId == null || toCol == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId" and "to"');
        }
        final columns = _columns(panel);
        final resolvedToCol = _resolveColumnId(columns, toCol);
        if (resolvedToCol == null) {
          return CliActionResult(ok: false, message: 'Target column not found: $toCol');
        }
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        final idx = cards.indexWhere((c) => c['id'] == cardId);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        cards[idx] = {...cards[idx], 'columnId': resolvedToCol};
        return CliActionResult(
          message: 'Card moved',
          stateUpdate: {'cards': cards},
        );
      case 'remove-card':
        final cardId = args['cardId'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        cards.removeWhere((c) => c['id'] == cardId);
        return CliActionResult(
          message: 'Card removed',
          stateUpdate: {'cards': cards},
        );
      case 'update-card':
        final cardId = args['cardId'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        final idx = cards.indexWhere((c) => c['id'] == cardId);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        final updated = <String, dynamic>{...cards[idx]};
        if (args.containsKey('title')) updated['title'] = args['title'];
        if (args.containsKey('description')) updated['description'] = args['description'];
        if (args.containsKey('color')) updated['color'] = args['color'];
        cards[idx] = updated;
        return CliActionResult(
          message: 'Card updated',
          stateUpdate: {'cards': cards},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  List<Map<String, dynamic>> _columns(BoardPanelInstance panel) =>
      List<Map<String, dynamic>>.from(
        (panel.state['columns'] as List<dynamic>?) ?? <Map<String, dynamic>>[],
      );

  List<Map<String, dynamic>> _cards(BoardPanelInstance panel) =>
      List<Map<String, dynamic>>.from(
        (panel.state['cards'] as List<dynamic>?) ?? <Map<String, dynamic>>[],
      );

  int _findColumnIndex(List<Map<String, dynamic>> columns, String idOrName) {
    final byId = columns.indexWhere((c) => c['id'] == idOrName);
    if (byId >= 0) return byId;
    return columns.indexWhere(
      (c) => (c['title'] as String?)?.toLowerCase() == idOrName.toLowerCase(),
    );
  }

  String? _resolveColumnId(List<Map<String, dynamic>> columns, String idOrName) {
    final idx = _findColumnIndex(columns, idOrName);
    if (idx < 0) return null;
    return columns[idx]['id'] as String?;
  }
}
