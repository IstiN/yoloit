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
      {'name': 'Alice', 'age': 30},
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
      expect(summary, contains('yoloit_note_append'));
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

    test('stringifies non-string table cells without casting', () async {
      const panel = BoardPanelInstance(
        id: 'p4',
        type: 'board.table',
        title: 'Mixed',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('| Alice | 30 |'));
      expect(summary, isNot(contains('Error:')));
      expect(summary, isNot(contains('is not a subtype')));
    });
  });

  group('buildFocusPanelSummary type guidance', () {
    setUpAll(() {
      CliServer.instance
        ..registerPanelHandler(const _KanbanTestHandler())
        ..registerPanelHandler(const _RunConfigsTestHandler())
        ..registerPanelHandler(const _QuietTerminalTestHandler())
        ..registerPanelHandler(const _CustomTestHandler());
    });

    test('sticky panel gets sticky guidance without a handler', () async {
      const panel = BoardPanelInstance(
        id: 'p-sticky',
        type: 'board.sticky',
        title: 'Sticky',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('(no content available)'));
      expect(summary, contains('yoloit_sticky_set'));
      expect(summary, contains('yoloit_sticky_append'));
      expect(summary, contains('yoloit_sticky_color'));
    });

    test('shape panel gets shape guidance without a handler', () async {
      const panel = BoardPanelInstance(
        id: 'p-shape',
        type: 'board.shape',
        title: 'Shape',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('(no content available)'));
      expect(summary, contains('yoloit_shape_get'));
      expect(summary, contains('yoloit_shape_set'));
    });

    test('kanban content lists columns and cards with kanban guidance', () async {
      const panel = BoardPanelInstance(
        id: 'p-kanban',
        type: 'board.kanban',
        title: 'Kanban',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('- **Todo** (2)'));
      expect(summary, contains('- **Done** (0)'));
      expect(summary, contains('  - Card one'));
      expect(summary, contains('add-card'));
      expect(summary, contains('move-card'));
    });

    test('run configs content lists configurations and sessions', () async {
      const panel = BoardPanelInstance(
        id: 'p-run',
        type: 'board.run_configs',
        title: 'Run',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('**Group:** dev'));
      expect(summary, contains('**Workspace:** /repo'));
      expect(summary, contains('- `web`: dart run'));
      expect(summary, contains('**Sessions:**'));
      expect(summary, contains('- `web` (running)'));
      expect(summary, contains('Run a config'));
    });

    test('terminal without output action renders config only', () async {
      const panel = BoardPanelInstance(
        id: 'p-term-quiet',
        type: 'board.terminal',
        title: 'Shell',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('**Configuration:**'));
      expect(summary, isNot(contains('Recent output')));
    });

    test('unknown type falls back to json content and generic guidance', () async {
      const panel = BoardPanelInstance(
        id: 'p-custom',
        type: 'board.widget.custom',
        title: 'Custom',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('"foo": "bar"'));
      expect(summary, contains('yoloit_panel_help'));
      expect(summary, contains('yoloit_do'));
    });

    test('table with many rows truncates and reports the omitted count', () async {
      CliServer.instance.registerPanelHandler(const _BigTableTestHandler());
      const panel = BoardPanelInstance(
        id: 'p-big',
        type: 'board.table',
        title: 'Big',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      );

      final summary = await buildFocusPanelSummary(panel);

      expect(summary, contains('| r9 | 9 |'));
      expect(summary, isNot(contains('| r11 | 11 |')));
      expect(summary, contains('*(+2 rows omitted)*'));

      // Restore the original table handler for other tests.
      CliServer.instance.registerPanelHandler(const _TableTestHandler());
    });
  });
}

class _KanbanTestHandler extends PanelCliHandler {
  const _KanbanTestHandler();

  @override
  String get typeId => 'board.kanban';

  @override
  List<String> get supportedActions => ['add-card', 'move-card'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'columns': [
      {
        'title': 'Todo',
        'cards': [
          {'id': 'c1', 'text': 'Card one'},
          {'id': 'c2', 'title': 'Card two'},
        ],
      },
      {'title': 'Done', 'cards': <Map<String, dynamic>>[]},
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

class _RunConfigsTestHandler extends PanelCliHandler {
  const _RunConfigsTestHandler();

  @override
  String get typeId => 'board.run_configs';

  @override
  List<String> get supportedActions => ['run', 'output', 'stop'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'group': 'dev',
    'workspacePath': '/repo',
    'configurations': [
      {'name': 'web', 'command': 'dart run'},
    ],
    'sessions': [
      {
        'config': {'name': 'web'},
        'status': 'running',
      },
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

class _QuietTerminalTestHandler extends PanelCliHandler {
  const _QuietTerminalTestHandler();

  @override
  String get typeId => 'board.terminal';

  @override
  List<String> get supportedActions => ['config'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'config': {'sessionId': 's2'},
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async =>
      const CliActionResult();
}

class _CustomTestHandler extends PanelCliHandler {
  const _CustomTestHandler();

  @override
  String get typeId => 'board.widget.custom';

  @override
  List<String> get supportedActions => [];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {'foo': 'bar'};

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async =>
      const CliActionResult();
}

class _BigTableTestHandler extends PanelCliHandler {
  const _BigTableTestHandler();

  @override
  String get typeId => 'board.table';

  @override
  List<String> get supportedActions => ['get'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'columns': [
      {'id': 'name', 'title': 'Name'},
      {'id': 'n'},
    ],
    'rows': [
      for (var i = 0; i < 12; i++) {'name': 'r$i', 'n': i},
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
