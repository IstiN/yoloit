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
      'columns': [
        for (var i = 0; i < columns.length; i++)
          {
            'index': i,
            'title': columns[i],
            'cards':
                cards
                    .where((card) => _cardColumnIndex(card, columns) == i)
                    .toList(),
          },
      ],
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
        final columns = _columns(panel);
        return CliActionResult(
          data: {
            'columns': [
              for (var i = 0; i < columns.length; i++)
                {'index': i, 'title': columns[i]},
            ],
          },
        );
      case 'cards':
        return CliActionResult(data: getContent(panel));
      case 'add-column':
        final name = args['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          return const CliActionResult(ok: false, message: 'Missing "name"');
        }
        final columns = _columns(panel)..add(name.trim());
        return CliActionResult(
          message: 'Column "$name" added',
          stateUpdate: {'columns': columns},
          data: {'columnIndex': columns.length - 1},
        );
      case 'rename-column':
        final col = args['columnId'] as String? ?? args['column'] as String?;
        final name = args['name'] as String?;
        if (col == null || name == null || name.trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "columnId" and "name"',
          );
        }
        final columns = _columns(panel);
        final idx = _findColumnIndex(columns, col);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Column not found: $col');
        }
        columns[idx] = name.trim();
        return CliActionResult(
          message: 'Column renamed to "$name"',
          stateUpdate: {'columns': columns},
        );
      case 'remove-column':
        final col = args['columnId'] as String? ?? args['column'] as String?;
        if (col == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "columnId"',
          );
        }
        final columns = _columns(panel);
        final idx = _findColumnIndex(columns, col);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Column not found: $col');
        }
        columns.removeAt(idx);
        final cards =
            _cards(panel)
                .where(
                  (card) =>
                      _cardColumnIndex(card, columns, removedIndex: idx) != idx,
                )
                .map((card) {
                  final old = _cardColumnIndex(
                    card,
                    columns,
                    removedIndex: idx,
                  );
                  return {...card, 'columnIndex': old > idx ? old - 1 : old}
                    ..remove('columnId');
                })
                .toList();
        return CliActionResult(
          message: 'Column removed',
          stateUpdate: {'columns': columns, 'cards': cards},
        );
      case 'add-card':
        final col = args['columnId'] as String? ?? args['column'] as String?;
        final title = args['title'] as String?;
        if (col == null || title == null || title.trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "columnId" and "title"',
          );
        }
        final columns = _columns(panel);
        final colIndex = _findColumnIndex(columns, col);
        if (colIndex < 0) {
          return CliActionResult(ok: false, message: 'Column not found: $col');
        }
        final cards = _cards(panel);
        final cardId = 'card-${DateTime.now().millisecondsSinceEpoch}';
        cards.add({
          'id': cardId,
          'title': title.trim(),
          'description': args['description'] as String? ?? '',
          'columnIndex': colIndex,
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
          return const CliActionResult(
            ok: false,
            message: 'Missing "cardId" and "to"',
          );
        }
        final columns = _columns(panel);
        final toIndex = _findColumnIndex(columns, toCol);
        if (toIndex < 0) {
          return CliActionResult(
            ok: false,
            message: 'Target column not found: $toCol',
          );
        }
        final cards = _cards(panel);
        final idx = cards.indexWhere((card) => card['id'] == cardId);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        cards[idx] = {...cards[idx], 'columnIndex': toIndex}
          ..remove('columnId');
        return CliActionResult(
          message: 'Card moved',
          stateUpdate: {'cards': cards},
        );
      case 'remove-card':
        final cardId = args['cardId'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = _cards(panel)
          ..removeWhere((card) => card['id'] == cardId);
        return CliActionResult(
          message: 'Card removed',
          stateUpdate: {'cards': cards},
        );
      case 'update-card':
        final cardId = args['cardId'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = _cards(panel);
        final idx = cards.indexWhere((card) => card['id'] == cardId);
        if (idx < 0) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        final updated = <String, dynamic>{...cards[idx]};
        if (args.containsKey('title')) updated['title'] = args['title'];
        if (args.containsKey('description')) {
          updated['description'] = args['description'];
        }
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

  List<String> _columns(BoardPanelInstance panel) => switch (panel
      .state['columns']) {
    final List<dynamic> entries =>
      entries.map((entry) {
        if (entry is Map<Object?, Object?>) {
          return (entry['title'] ?? entry['name'] ?? entry['id']).toString();
        }
        return entry.toString();
      }).toList(),
    _ => ['Backlog', 'Todo', 'In Progress', 'Done'],
  };

  List<Map<String, dynamic>> _cards(BoardPanelInstance panel) => switch (panel
      .state['cards']) {
    final List<dynamic> entries =>
      entries
          .whereType<Map<Object?, Object?>>()
          .map(
            (entry) => {
              for (final item in entry.entries) item.key.toString(): item.value,
            },
          )
          .toList(),
    _ => <Map<String, dynamic>>[],
  };

  int _findColumnIndex(List<String> columns, String idOrName) {
    final byIndex = int.tryParse(idOrName);
    if (byIndex != null && byIndex >= 0 && byIndex < columns.length) {
      return byIndex;
    }
    return columns.indexWhere(
      (column) => column.toLowerCase() == idOrName.toLowerCase(),
    );
  }

  int _cardColumnIndex(
    Map<String, dynamic> card,
    List<String> columns, {
    int? removedIndex,
  }) {
    final rawIndex = card['columnIndex'];
    if (rawIndex is int) return rawIndex.clamp(0, columns.length);
    if (rawIndex is num) return rawIndex.toInt().clamp(0, columns.length);
    final columnId = card['columnId']?.toString();
    if (columnId != null) {
      final idx = _findColumnIndex(columns, columnId);
      if (idx >= 0) return idx;
    }
    return removedIndex ?? 0;
  }
}
