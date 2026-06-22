import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/chat/panel_context_builder.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class _NoteTestHandler extends PanelCliHandler {
  const _NoteTestHandler();

  @override
  String get typeId => 'board.note.markdown';

  @override
  List<String> get supportedActions => ['get', 'set', 'append'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'markdown': panel.state['markdown'] ?? '',
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async =>
      const CliActionResult();
}

class _TerminalTestHandler extends PanelCliHandler {
  const _TerminalTestHandler();

  @override
  String get typeId => 'board.terminal';

  @override
  List<String> get supportedActions => ['config', 'output'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'config': {'sessionId': 's1', 'workingDir': '/repo'},
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    if (action == 'output') {
      return const CliActionResult(
        data: {
          'lines': ['line 1', 'line 2'],
          'total': 2,
        },
      );
    }
    return const CliActionResult();
  }
}

class _TableTestHandler extends PanelCliHandler {
  const _TableTestHandler();

  @override
  String get typeId => 'board.table';

  @override
  List<String> get supportedActions => ['get', 'add-row'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'columns': [
      {'id': 'name', 'title': 'Name'},
      {'id': 'age', 'title': 'Age'},
    ],
    'rows': [
      {'name': 'Alice', 'age': '30'},
      {'name': 'Bob', 'age': '25'},
    ],
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async =>
      const CliActionResult();
}

void main() {
  setUpAll(() {
    CliServer.instance
      ..registerPanelHandler(const _NoteTestHandler())
      ..registerPanelHandler(const _TerminalTestHandler())
      ..registerPanelHandler(const _TableTestHandler());
  });

  group('buildFocusPanelSummary', () {
    test('formats markdown note content and guidance', () async {
      const panel = BoardPanelInstance(
        id: 'p1',
        type: 'board.note.markdown',
        title: 'My note',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        state: {'markdown': '# Hello'},
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('### Focus panel'));
      expect(summary, contains('- id: `p1`'));
      expect(summary, contains('# Hello'));
      expect(summary, contains('How to work with this panel'));
      expect(summary, contains('yoloit_do'));
    });

    test('formats terminal content with recent output', () async {
      const panel = BoardPanelInstance(
        id: 'p2',
        type: 'board.terminal',
        title: 'Shell',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('Recent output'));
      expect(summary, contains('line 1'));
      expect(summary, contains('line 2'));
      expect(summary, contains('workingDir'));
    });

    test('formats table as markdown table', () async {
      const panel = BoardPanelInstance(
        id: 'p3',
        type: 'board.table',
        title: 'People',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('| Name | Age |'));
      expect(summary, contains('| Alice | 30 |'));
      expect(summary, contains('| Bob | 25 |'));
    });
  });
}
