import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/core/cli/handlers/filetree_handler.dart';
import 'package:yoloit/core/cli/handlers/kanban_handler.dart';
import 'package:yoloit/core/cli/handlers/note_handler.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panelForType(String type) => BoardPanelInstance(
      id: 'panel-$type',
      type: type,
      title: 'Test Panel',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
      state: const {},
    );

/// All handlers under test with their expected typeId.
final List<(PanelCliHandler, String)> allHandlers = [
  (const NoteCliHandler(), 'board.note.markdown'),
  (const KanbanCliHandler(), 'board.kanban'),
  (const ChecklistCliHandler(), 'board.checklist'),
  (const TimerCliHandler(), 'board.timer'),
  (const CodeSnippetCliHandler(), 'board.code.snippet'),
  (const FileTreeCliHandler(), 'board.filetree'),
];

void main() {
  group('Multitype board — each handler has correct typeId', () {
    for (final (handler, expectedTypeId) in allHandlers) {
      test('${handler.runtimeType} typeId is $expectedTypeId', () {
        expect(handler.typeId, expectedTypeId);
      });
    }
  });

  group('Multitype board — each handler has non-empty supportedActions', () {
    for (final (handler, _) in allHandlers) {
      test('${handler.runtimeType} has supportedActions', () {
        expect(handler.supportedActions, isNotEmpty);
      });
    }
  });

  group('Multitype board — getContent returns map from default state', () {
    for (final (handler, typeId) in allHandlers) {
      test('${handler.runtimeType} getContent returns map', () {
        final panel = _panelForType(typeId);
        final content = handler.getContent(panel);
        expect(content, isA<Map<String, dynamic>>());
        expect(content, isNotNull);
      });
    }
  });

  group('Multitype board — unknown action returns ok=false for each handler', () {
    for (final (handler, typeId) in allHandlers) {
      test('${handler.runtimeType} rejects unknown action', () async {
        final panel = _panelForType(typeId);
        final r = await handler.handleAction('__unknown_action__', {}, panel);
        expect(r.ok, isFalse);
      });
    }
  });

  group('Multitype board — cross-type action rejection', () {
    test('NoteCliHandler rejects kanban-specific actions', () async {
      final noteHandler = const NoteCliHandler();
      final panel = _panelForType('board.note.markdown');

      for (final kanbanAction in ['columns', 'cards', 'add-column', 'add-card', 'move-card']) {
        final r = await noteHandler.handleAction(kanbanAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'NoteCliHandler should reject kanban action "$kanbanAction"');
      }
    });

    test('KanbanCliHandler rejects note-specific actions', () async {
      final kanbanHandler = const KanbanCliHandler();
      final panel = _panelForType('board.kanban');

      for (final noteAction in ['get', 'set', 'append', 'wrap', 'nowrap']) {
        final r = await kanbanHandler.handleAction(noteAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'KanbanCliHandler should reject note action "$noteAction"');
      }
    });

    test('ChecklistCliHandler rejects timer-specific actions', () async {
      final checklistHandler = const ChecklistCliHandler();
      final panel = _panelForType('board.checklist');

      for (final timerAction in ['start', 'pause', 'resume', 'reset', 'status']) {
        final r = await checklistHandler.handleAction(timerAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'ChecklistCliHandler should reject timer action "$timerAction"');
      }
    });

    test('TimerCliHandler rejects checklist-specific actions', () async {
      final timerHandler = const TimerCliHandler();
      final panel = _panelForType('board.timer');

      for (final checklistAction in ['items', 'add', 'check', 'uncheck', 'remove', 'rename']) {
        final r = await timerHandler.handleAction(checklistAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'TimerCliHandler should reject checklist action "$checklistAction"');
      }
    });

    test('CodeSnippetCliHandler rejects filetree-specific actions', () async {
      final codeHandler = const CodeSnippetCliHandler();
      final panel = _panelForType('board.code.snippet');

      for (final treeAction in ['list', 'expand', 'collapse', 'set-root', 'refresh']) {
        final r = await codeHandler.handleAction(treeAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'CodeSnippetCliHandler should reject filetree action "$treeAction"');
      }
    });

    test('FileTreeCliHandler rejects code snippet-specific actions', () async {
      final treeHandler = const FileTreeCliHandler();
      final panel = _panelForType('board.filetree');

      // 'get' and 'set' are code snippet actions not in filetree
      for (final codeAction in ['get', 'set']) {
        final r = await treeHandler.handleAction(codeAction, {}, panel);
        expect(r.ok, isFalse,
            reason: 'FileTreeCliHandler should reject code snippet action "$codeAction"');
      }
    });
  });

  group('Multitype board — all handlers are distinct types', () {
    test('all typeIds are unique', () {
      final typeIds = allHandlers.map((e) => e.$2).toList();
      final uniqueTypeIds = typeIds.toSet();
      expect(uniqueTypeIds.length, typeIds.length,
          reason: 'All handlers should have unique typeIds');
    });

    test('no handler claims another handler\'s typeId', () {
      for (final (handler, expectedTypeId) in allHandlers) {
        for (final (_, otherTypeId) in allHandlers) {
          if (otherTypeId != expectedTypeId) {
            expect(handler.typeId, isNot(otherTypeId),
                reason:
                    '${handler.runtimeType} should not claim typeId "$otherTypeId"');
          }
        }
      }
    });
  });
}
