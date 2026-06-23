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
    'send-card-to-chat',
    'paste',
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
        final cardId = args['cardId'] as String? ?? args['card'] as String?;
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
        final idx = _cardIndexByIdOrTitle(cards, cardId);
        if (idx == null) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        cards[idx] = {...cards[idx], 'columnIndex': toIndex}
          ..remove('columnId');
        return CliActionResult(
          message: 'Card moved',
          stateUpdate: {'cards': cards},
        );
      case 'remove-card':
        final cardId = args['cardId'] as String? ?? args['card'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = _cards(panel)
          ..removeWhere((card) => _cardMatchesIdOrTitle(card, cardId));
        return CliActionResult(
          message: 'Card removed',
          stateUpdate: {'cards': cards},
        );
      case 'update-card':
        final cardId = args['cardId'] as String? ?? args['card'] as String?;
        if (cardId == null) {
          return const CliActionResult(ok: false, message: 'Missing "cardId"');
        }
        final cards = _cards(panel);
        final idx = _cardIndexByIdOrTitle(cards, cardId);
        if (idx == null) {
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
      case 'send-card-to-chat':
        final cardId = args['cardId'] as String? ?? args['card'] as String?;
        final targetPanelId = args['targetPanelId'] as String?;
        if (cardId == null || targetPanelId == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "cardId" and "targetPanelId"',
          );
        }
        final cards = _cards(panel);
        final idx = _cardIndexByIdOrTitle(cards, cardId);
        if (idx == null) {
          return CliActionResult(ok: false, message: 'Card not found: $cardId');
        }
        final card = cards[idx];
        final title = card['title']?.toString().trim() ?? '';
        final description = card['description']?.toString().trim() ?? '';
        final cardText = <String>[
          if (title.isNotEmpty) title,
          if (description.isNotEmpty) description,
        ].join('\n\n');
        return CliActionResult(
          message: 'Card queued for chat panel $targetPanelId',
          data: {'targetPanelId': targetPanelId, 'cardText': cardText},
          additionalStateUpdates: {
            targetPanelId: {
              '_cliPendingMessage': cardText,
              '_cliPendingAttachments': <String>[],
            },
          },
        );
      case 'paste':
        final text = args['text'] as String?;
        final columnIndex = (args['columnIndex'] as num?)?.toInt() ?? 0;
        if (text == null || text.trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "text" to paste',
          );
        }
        final lines = text.trim().split('\n');
        final title = lines.first.trim();
        final description = lines.skip(1).join('\n').trim();
        final cards = List<Map<String, dynamic>>.from(_cards(panel));
        final columns = _columns(panel);
        cards.add({
          'id': 'card-${DateTime.now().millisecondsSinceEpoch}',
          'title': title.length > 120 ? '${title.substring(0, 120)}…' : title,
          'description': description,
          'columnIndex': columnIndex.clamp(0, columns.length - 1),
        });
        return CliActionResult(
          message: 'Card pasted to ${columns[columnIndex.clamp(0, columns.length - 1)]}',
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

  int? _cardIndexByIdOrTitle(
    List<Map<String, dynamic>> cards,
    String idOrTitle,
  ) {
    for (var i = 0; i < cards.length; i++) {
      if (cards[i]['id']?.toString() == idOrTitle) return i;
    }
    final needle = idOrTitle.toLowerCase().trim();
    for (var i = 0; i < cards.length; i++) {
      final title = cards[i]['title']?.toString().toLowerCase().trim() ?? '';
      if (title == needle || title.contains(needle)) return i;
    }
    return null;
  }

  bool _cardMatchesIdOrTitle(Map<String, dynamic> card, String idOrTitle) {
    if (card['id']?.toString() == idOrTitle) return true;
    final needle = idOrTitle.toLowerCase().trim();
    final title = card['title']?.toString().toLowerCase().trim() ?? '';
    return title == needle || title.contains(needle);
  }

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

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'columns': const CliActionHelp(description: 'List kanban columns'),
    'cards': const CliActionHelp(description: 'List kanban columns with cards'),
    'add-column': const CliActionHelp(
      description: 'Add a kanban column',
      params: {'name': 'Column name'},
    ),
    'rename-column': const CliActionHelp(
      description: 'Rename a column by index or name',
      params: {'column': 'Column index or name', 'name': 'New column name'},
    ),
    'remove-column': const CliActionHelp(
      description: 'Remove a column by index or name',
      params: {'column': 'Column index or name'},
    ),
    'add-card': const CliActionHelp(
      description: 'Add a card to a column',
      params: {
        'column': 'Column index or name',
        'title': 'Card title',
        'description': 'Optional description',
        'color': 'Optional color',
      },
    ),
    'move-card': const CliActionHelp(
      description: 'Move a card to another column by id or title',
      params: {'cardId': 'Card id or title', 'to': 'Target column index or name'},
    ),
    'remove-card': const CliActionHelp(
      description: 'Remove a card by id or title',
      params: {'cardId': 'Card id or title'},
    ),
    'update-card': const CliActionHelp(
      description: 'Update card title, description, or color by id or title',
      params: {
        'cardId': 'Card id or title',
        'title': 'New title',
        'description': 'New description',
        'color': 'Color',
      },
    ),
    'send-card-to-chat': const CliActionHelp(
      description:
          'Copy a kanban card into a chat panel as a pending message by id or title',
      params: {
        'cardId': 'Card id or title',
        'targetPanelId': 'Target chat panel id',
      },
    ),
    'paste': const CliActionHelp(
      description: 'Create a card from clipboard text',
      params: {
        'text': 'Text to paste (first line becomes title)',
        'columnIndex': 'Target column index (default 0)',
      },
    ),
  };
}
