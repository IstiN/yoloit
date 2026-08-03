import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/assistant/widgets/assistant_tool_executor.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

typedef FakeToolHandler =
    String Function(String functionName, Map<String, Object?> arguments);

class _RecordedInvoke {
  _RecordedInvoke(this.functionName, this.arguments);

  final String functionName;
  final Map<String, Object?> arguments;
}

class _FakeDelegate implements YoloitToolExecutor {
  _FakeDelegate({this.handler});

  final FakeToolHandler? handler;
  final List<_RecordedInvoke> calls = [];

  Map<String, Object?> get lastArguments => calls.last.arguments;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    calls.add(
      _RecordedInvoke(functionName, Map<String, Object?>.from(arguments)),
    );
    final h = handler;
    if (h != null) return h(functionName, arguments);
    return '{"ok": true}';
  }
}

/// Builds a handler that serves `yoloit_boards` / `yoloit_panels` /
/// `yoloit_panel` responses from an in-memory board model.
FakeToolHandler boardHandler({
  required Map<String, List<Map<String, Object?>>> panelsByBoard,
  Map<String, String> panelDetailsByKey = const <String, String>{},
}) {
  return (String functionName, Map<String, Object?> arguments) {
    if (functionName == 'yoloit_boards') {
      return jsonEncode(<String, Object?>{
        'boards': <Map<String, Object?>>[
          for (final id in panelsByBoard.keys) <String, Object?>{'id': id},
        ],
      });
    }
    if (functionName == 'yoloit_panels') {
      final boardId = '${arguments['id_or_name'] ?? ''}';
      return jsonEncode(<String, Object?>{
        'panels': panelsByBoard[boardId] ?? const <Map<String, Object?>>[],
      });
    }
    if (functionName == 'yoloit_panel') {
      final key = '${arguments['board']}/${arguments['panel']}';
      return panelDetailsByKey[key] ?? '{"ok": true}';
    }
    return '{"ok": true}';
  };
}

Map<String, Object?> terminalPanel(
  String id,
  String title, {
  num zIndex = 0,
  bool hidden = false,
}) {
  return <String, Object?>{
    'id': id,
    'type': 'board.terminal',
    'title': title,
    'zIndex': zIndex,
    'hidden': hidden,
  };
}

Map<String, Object?> notePanel(
  String id,
  String title, {
  num zIndex = 0,
  bool hidden = false,
}) {
  return <String, Object?>{
    'id': id,
    'type': 'board.note.markdown',
    'title': title,
    'zIndex': zIndex,
    'hidden': hidden,
  };
}

void main() {
  late _FakeDelegate delegate;
  late List<Map<String, Object?>> focusCalls;

  AssistantToolExecutor buildExecutor({String? targetPanelId}) {
    return AssistantToolExecutor(
      delegate: delegate,
      assistantPanelId: 'assistant-1',
      assistantPanelTitle: 'Assistant',
      targetPanelId: targetPanelId,
      onFocusPanel: (Map<String, Object?> args) async => focusCalls.add(args),
    );
  }

  setUp(() {
    delegate = _FakeDelegate();
    focusCalls = <Map<String, Object?>>[];
  });

  group('note tool retargeting (_retargetNoteToolIfNeeded)', () {
    test('retargets empty panel to last known note panel', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], 'note-1');
    });

    test('keeps an explicit real panel', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'panel': 'other-note',
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], 'other-note');
    });

    test('retargets when panel is the assistant panel id', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'panel': 'assistant-1',
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], 'note-1');
    });

    test('retargets when panel is the assistant panel title', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'panel': 'Assistant',
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], 'note-1');
    });

    test('retargets explicit panel when message mentions previous note', () async {
      final executor =
          buildExecutor()
            ..lastTargetNotePanelId = 'note-1'
            ..userMessage = 'добавь в нее еще текст';
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'panel': 'other-note',
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], 'note-1');
    });

    test('does nothing when no last note panel is known', () async {
      final executor = buildExecutor();
      await executor.invoke('yoloit_note_append', <String, Object?>{
        'text': 'hello',
      });
      expect(delegate.lastArguments['panel'], isNull);
    });

    test('ignores note:create', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_note_create', <String, Object?>{
        'title': 'New',
      });
      expect(delegate.lastArguments['panel'], isNull);
    });

    test('ignores non-note tools', () async {
      final executor = buildExecutor()..lastTargetNotePanelId = 'note-1';
      await executor.invoke('yoloit_panel_rename', <String, Object?>{
        'panel': 'panel-7',
        'title': 'X',
      });
      expect(delegate.lastArguments['panel'], 'panel-7');
    });
  });

  group('note panel guard (_ensureNoteToolHasRealPanel)', () {
    test('resolves a real note panel when panel arg is empty', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[notePanel('n1', 'Mermaid diagram')],
          },
        ),
      );
      final executor =
          buildExecutor()..userMessage = 'update the mermaid diagram note';
      await executor.invoke(
        'yoloit_note_append',
        <String, Object?>{'text': 'x'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'n1');
      expect(delegate.lastArguments['board'], 'b1');
    });

    test('leaves assistant panel untouched when no note can be resolved', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'update the note';
      await executor.invoke(
        'yoloit_note_append',
        <String, Object?>{'panel': 'Assistant', 'text': 'x'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'Assistant');
    });
  });

  group('terminal targeting (_resolveTerminalTarget / _isTerminalPanelRef)', () {
    test('resolves the best matching terminal across boards', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              terminalPanel('t1', 'Build logs', zIndex: 1),
            ],
            'b2': <Map<String, Object?>>[
              terminalPanel('t2', 'Server', zIndex: 9),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show build output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 't1');
      expect(delegate.lastArguments['board'], 'b1');
    });

    test('prefers the higher zIndex when scores tie', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              terminalPanel('t1', 'Logs', zIndex: 1),
              terminalPanel('t2', 'Shell', zIndex: 5),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'tail the output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 't2');
    });

    test('skips hidden, non-terminal and id-less panels', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              terminalPanel('t-hidden', 'Hidden', hidden: true, zIndex: 99),
              notePanel('n1', 'Not a terminal', zIndex: 99),
              terminalPanel('', 'No id', zIndex: 99),
              terminalPanel('t9', 'Logs'),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 't9');
    });

    test('keeps an explicit panel that resolves to a real terminal id', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[terminalPanel('t1', 'Build logs')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{'panel': 't1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 't1');
      expect(delegate.lastArguments['board'], isNull);
    });

    test('keeps an explicit panel that matches a terminal title', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[terminalPanel('t1', 'Build logs')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{'panel': 'Build logs'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'Build logs');
    });

    test('retargets when the explicit panel is not a terminal', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              notePanel('n1', 'Specs'),
              terminalPanel('t2', 'Logs'),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{'panel': 'Specs'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 't2');
    });

    test('leaves args unchanged when no terminal panel exists', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[notePanel('n1', 'Specs')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], isNull);
      expect(delegate.lastArguments['board'], isNull);
    });

    test('leaves args unchanged when the boards payload is malformed', () async {
      delegate = _FakeDelegate(
        handler: (String functionName, Map<String, Object?> arguments) {
          if (functionName == 'yoloit_boards') return 'not json';
          return '{"ok": true}';
        },
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], isNull);
    });

    test('leaves args unchanged when the delegate throws', () async {
      delegate = _FakeDelegate(
        handler: (String functionName, Map<String, Object?> arguments) {
          if (functionName == 'yoloit_boards') {
            throw StateError('boom');
          }
          return '{"ok": true}';
        },
      );
      final executor = buildExecutor()..userMessage = 'show output';
      await executor.invoke(
        'yoloit_terminal_output',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], isNull);
    });
  });

  group('panel lookup retargeting (_retargetPanelLookupToRealNoteIfNeeded)', () {
    test('resolves a note panel for panel:focus with note intent', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              notePanel('n1', 'Mermaid states', zIndex: 1),
              notePanel('n2', 'Random', zIndex: 2),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show the mermaid note';
      await executor.invoke(
        'yoloit_panel_focus',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'n1');
      expect(delegate.lastArguments['board'], 'b1');
    });

    test('retargets the plain panel command with russian note intent', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[notePanel('n1', 'Диаграмма потоков')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'покажи заметку';
      await executor.invoke(
        'yoloit_panel',
        <String, Object?>{'panel': 'assistant-1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'n1');
    });

    test('uses markdown content when the title score is low', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              notePanel('n1', 'Notes', zIndex: 1),
              notePanel('n2', 'Random stuff', zIndex: 5),
            ],
          },
          panelDetailsByKey: <String, String>{
            'b1/n1': jsonEncode(<String, Object?>{
              'state': <String, Object?>{
                'markdown': '# Parser\nDiagram of the parser flow',
              },
            }),
            'b1/n2': jsonEncode(<String, Object?>{
              'content': <String, Object?>{'markdown': 'nothing here'},
            }),
          },
        ),
      );
      final executor =
          buildExecutor()..userMessage = 'show diagram of parser flow';
      await executor.invoke(
        'yoloit_panel_focus',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'n1');
    });

    test('does nothing without a note lookup intent', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[notePanel('n1', 'Specs')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'focus the terminal';
      await executor.invoke(
        'yoloit_panel_focus',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], isNull);
    });

    test('keeps an explicit non-assistant panel even with intent', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[notePanel('n1', 'Specs')],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show the note';
      await executor.invoke(
        'yoloit_panel_focus',
        <String, Object?>{'panel': 'some-panel'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], 'some-panel');
    });

    test('leaves args unchanged when only hidden notes exist', () async {
      delegate = _FakeDelegate(
        handler: boardHandler(
          panelsByBoard: <String, List<Map<String, Object?>>>{
            'b1': <Map<String, Object?>>[
              notePanel('n1', 'Specs', hidden: true),
            ],
          },
        ),
      );
      final executor = buildExecutor()..userMessage = 'show the note';
      await executor.invoke(
        'yoloit_panel_focus',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(delegate.lastArguments['panel'], isNull);
    });
  });

  group('panel:create auto-focus (_createdPanelFromResult)', () {
    test('focuses the created panel parsed from stdout payload', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': true,
                'stdout': jsonEncode(<String, Object?>{
                  'panel': <String, Object?>{'id': 'p9', 'title': 'Fresh'},
                }),
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{'board': 'b1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(focusCalls, <Map<String, Object?>>[
        <String, Object?>{'board': 'b1', 'panel': 'p9'},
      ]);
    });

    test('focuses the created panel from a direct payload', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': true,
                'panel': <String, Object?>{'id': 'p7'},
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(boardName: 'MyBoard'),
      );
      expect(focusCalls, <Map<String, Object?>>[
        <String, Object?>{'board': 'MyBoard', 'panel': 'p7'},
      ]);
    });

    test('does not focus when the tool result failed', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': false,
                'panel': <String, Object?>{'id': 'p7'},
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{'board': 'b1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(focusCalls, isEmpty);
    });

    test('does not focus without a runtime context', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': true,
                'panel': <String, Object?>{'id': 'p7'},
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke('yoloit_panel_create', <String, Object?>{
        'board': 'b1',
      });
      expect(focusCalls, isEmpty);
    });

    test('does not focus when the created panel id is empty', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': true,
                'panel': <String, Object?>{'id': ''},
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{'board': 'b1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(focusCalls, isEmpty);
    });

    test('does not focus on a non-JSON result', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => 'oops',
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{'board': 'b1'},
        runtimeContext: const ChatRuntimeContext(boardId: 'b1'),
      );
      expect(focusCalls, isEmpty);
    });

    test('does not focus when no board can be determined', () async {
      delegate = _FakeDelegate(
        handler:
            (String functionName, Map<String, Object?> arguments) => jsonEncode(
              <String, Object?>{
                'ok': true,
                'panel': <String, Object?>{'id': 'p7'},
              },
            ),
      );
      final executor = buildExecutor();
      await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{},
        runtimeContext: const ChatRuntimeContext(),
      );
      expect(focusCalls, isEmpty);
    });
  });

  group('focus panel defaulting (_retargetToFocusPanelIfNeeded)', () {
    test('defaults panel argument to the focus panel', () async {
      final executor = buildExecutor(targetPanelId: 'focus-1');
      await executor.invoke('yoloit_panel_rename', <String, Object?>{
        'title': 'X',
      });
      expect(delegate.lastArguments['panel'], 'focus-1');
    });

    test('skips board-level commands', () async {
      final executor = buildExecutor(targetPanelId: 'focus-1');
      await executor.invoke('yoloit_boards', <String, Object?>{});
      expect(delegate.lastArguments.containsKey('panel'), isFalse);
    });

    test('skips panel:create', () async {
      final executor = buildExecutor(targetPanelId: 'focus-1');
      await executor.invoke('yoloit_panel_create', <String, Object?>{});
      expect(delegate.lastArguments.containsKey('panel'), isFalse);
    });

    test('skips terminal commands', () async {
      final executor = buildExecutor(targetPanelId: 'focus-1');
      await executor.invoke('yoloit_terminal_output', <String, Object?>{});
      expect(delegate.lastArguments.containsKey('panel'), isFalse);
    });

    test('keeps an explicitly provided panel', () async {
      final executor = buildExecutor(targetPanelId: 'focus-1');
      await executor.invoke('yoloit_panel_rename', <String, Object?>{
        'panel': 'explicit-1',
        'title': 'X',
      });
      expect(delegate.lastArguments['panel'], 'explicit-1');
    });
  });

  group('onToolCompleted', () {
    test('reports the tool command, mutated args and success flag', () async {
      final completions = <List<Object?>>[];
      final executor =
          buildExecutor()
            ..onToolCompleted = (
              String toolCommand,
              Map<String, Object?> arguments,
              String result,
              bool success,
            ) {
              completions.add(<Object?>[toolCommand, arguments, success]);
            };
      await executor.invoke('yoloit_panel_rename', <String, Object?>{
        'panel': 'p1',
        'title': 'X',
      });
      expect(completions, hasLength(1));
      expect(completions.single[0], 'panel:rename');
      expect(
        (completions.single[1]! as Map<String, Object?>)['panel'],
        'p1',
      );
      expect(completions.single[2], isTrue);
    });
  });
}
