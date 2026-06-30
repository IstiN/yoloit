import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

const _manifest = flm.LocalModelManifest(
  id: 'test-local-chat-tools',
  displayName: 'Test Local Chat Tools',
  description: 'fixture',
  runtimeAdapter: flm.RuntimeAdapter.mlxLm,
  tasks: <flm.ModelTask>[flm.ModelTask.chat],
  source: flm.ModelSource(
    provider: 'local',
    repo: 'test/tools',
    revision: 'main',
    license: 'mit',
  ),
  packaging: flm.PackagingSpec(
    releaseTag: 'test',
    archiveName: 'test.tar',
    chunkSizeBytes: 1,
    assetPrefix: 'test',
  ),
  requirements: flm.SystemRequirements(
    platform: 'macos-apple-silicon',
    minMemoryGb: 4,
    recommendedMemoryGb: 8,
    notes: <String>[],
  ),
  capabilities: flm.CapabilitySpec(
    audioInput: false,
    audioOutput: false,
    toolCalling: true,
  ),
);

const _qwenTinyManifest = flm.LocalModelManifest(
  id: 'qwen3-0.6b-4bit',
  displayName: 'Qwen3 0.6B 4bit',
  description: 'fixture',
  runtimeAdapter: flm.RuntimeAdapter.mlxLm,
  tasks: <flm.ModelTask>[flm.ModelTask.chat],
  source: flm.ModelSource(
    provider: 'huggingface',
    repo: 'mlx-community/Qwen3-0.6B-4bit',
    revision: 'main',
    license: 'apache-2.0',
  ),
  packaging: flm.PackagingSpec(
    releaseTag: 'test',
    archiveName: 'test.tar',
    chunkSizeBytes: 1,
    assetPrefix: 'test',
  ),
  requirements: flm.SystemRequirements(
    platform: 'macos-apple-silicon',
    minMemoryGb: 4,
    recommendedMemoryGb: 8,
    notes: <String>[],
  ),
  capabilities: flm.CapabilitySpec(
    audioInput: false,
    audioOutput: false,
    toolCalling: true,
  ),
);

void main() {
  test('catalog exposes CLI tools as local-model function tools', () {
    final names = YoloitCliToolCatalog.localTools.map((t) => t.name).toList();
    expect(YoloitCliToolCatalog.tools.length, greaterThanOrEqualTo(65));
    expect(
      names,
      containsAll(<String>[
        'get_tools',
        'bmk', // board:create
        'pmk', // panel:create
        'nap', // note:append
        'kadk', // kanban:add-card
        'rls', // run:list
      ]),
    );
    expect(names.toSet(), hasLength(names.length));
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-zA-Z0-9_]+$')));
    }
  });

  test('catalog resolves compact, full, and command-style tool names', () {
    expect(YoloitCliToolCatalog.byFunctionName('bmk')?.command, 'board:create');
    expect(
      YoloitCliToolCatalog.byFunctionName('yoloit_board_create')?.command,
      'board:create',
    );
    expect(
      YoloitCliToolCatalog.byFunctionName('board:create')?.command,
      'board:create',
    );
    expect(
      YoloitCliToolCatalog.byFunctionName('note_create')?.command,
      'note:create',
    );
    expect(
      YoloitCliToolCatalog.byFunctionName('note_append')?.command,
      'note:append',
    );
  });

  test('catalog can expose a filtered local-model tool set', () {
    final tools = YoloitCliToolCatalog.localToolsFor(
      disabledFunctionNames: const <String>{'yoloit_board_delete'},
    );
    final names = tools.map((tool) => tool.name).toSet();

    expect(names, contains('get_tools'));
    expect(names, contains('bmk')); // board:create
    expect(names, isNot(contains('bdl'))); // board:delete disabled
    expect(
      YoloitCliToolCatalog.compactToolsJson(
        disabledFunctionNames: const <String>{'bdl'},
      ),
      isNot(contains('bdl')),
    );
  });

  test('local tool catalog stays in sync with CLI help tools output', () async {
    final result = await Process.run('tools/yoloit', const <String>[
      'help',
      '--format',
      'tools',
    ], runInShell: false);
    expect(result.exitCode, 0);
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final helpCommands =
        (decoded['tools'] as List)
            .map((tool) => (tool as Map)['name'] as String)
            .toSet();
    final catalogCommands =
        YoloitCliToolCatalog.tools.map((tool) => tool.command).toSet();

    expect(
      catalogCommands,
      helpCommands.difference(const <String>{'lm:generate', 'process-command'}),
    );
  });

  test(
    'executor builds preview command with runtime board and panel defaults',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke(
                  'yoloit_note_append',
                  <String, Object?>{'text': 'hello'},
                  runtimeContext: const ChatRuntimeContext(
                    boardId: 'board-1',
                    panelId: 'panel-1',
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(result['executed'], isFalse);
      expect(result['command'], 'yoloit note:append board-1 panel-1 hello');
    },
  );

  test(
    'executor quotes arguments with spaces and json payloads for shell argv',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke(
                  'yoloit_chart_create',
                  <String, Object?>{
                    'b': 'Personal Expenses',
                    't': 'Expenses Bar Chart',
                    'type': 'bar',
                  },
                ),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(
        result['command'],
        "yoloit chart:create 'Personal Expenses' 'Expenses Bar Chart' bar",
      );
    },
  );

  test(
    'executor recognizes compact lowercase keys from tool schema',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke(
                  'chlt',
                  <String, Object?>{
                    'b': 'board-1',
                    'p': 'chart-1',
                    'tablepanelid': 'table-1',
                  },
                ),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(result['executed'], isFalse);
      expect(
        result['command'],
        "yoloit chart:link-table board-1 chart-1 table-1",
      );
    },
  );

  test(
    'executor quotes json body argument for do action',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke(
                  'yoloit_do',
                  <String, Object?>{
                    'b': 'Personal Expenses',
                    'p': 'expenses-table',
                    'a': 'add-row',
                    'j': '{"cells":{"Категория":"Аренда","Сумма":25000}}',
                  },
                ),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(
        result['command'],
        "yoloit do 'Personal Expenses' expenses-table add-row "
        "'{\"cells\":{\"Категория\":\"Аренда\",\"Сумма\":25000}}'",
      );
    },
  );

  test('executor renders board:grid with dashed flags', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'bgr',
                <String, Object?>{
                  'b': 'My Board',
                  'on_or_off_or_reset': 'on',
                  'cell': 220,
                  'spacing': 24,
                  'arrange': true,
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit board:grid 'My Board' on --cell 220 --spacing 24 --arrange",
    );
  });

  test('executor validates board:grid enum value', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'bgr',
                <String, Object?>{
                  'b': 'My Board',
                  'on_or_off_or_reset': 'maybe',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isFalse);
    expect(result['executed'], isFalse);
    expect(result['error'], contains('Invalid value'));
  });

  test('executor rejects placeholder ids for panel/session args', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'tout',
                <String, Object?>{
                  'b': 'board-1',
                  'p': 'yoloit_board_grid',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isFalse);
    expect(result['error'], contains('placeholder'));
  });

  test('executor renders terminal:set-dir with alias', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'tsd',
                <String, Object?>{
                  'b': 'board-1',
                  'p': 'Terminal',
                  'd': '/Users/me/project',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit terminal:set-dir board-1 Terminal /Users/me/project",
    );
  });

  test('executor validates yolochat:terminal text is not an agent name', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'ctm',
                <String, Object?>{
                  'tx': 'copilot',
                  'b': 'board-1',
                  'p': 'Terminal',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit yolochat:terminal copilot --board board-1 --panel Terminal",
    );
  });

  test('executor renders shape:set with dashed flags', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'shs',
                <String, Object?>{
                  'b': 'board-1',
                  'p': 'Diamond',
                  'f': '#22C55E',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit shape:set board-1 Diamond --fill '#22C55E'",
    );
  });

  test('executor renders shape:set fill only without text placeholder', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'yoloit_shape_set',
                <String, Object?>{
                  'b': 'board-1',
                  'p': 'p-1782029161949503',
                  'fill': '#22C55E',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit shape:set board-1 p-1782029161949503 --fill '#22C55E'",
    );
  });

  test('executor renders sticky:color with dashed flag', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'stc',
                <String, Object?>{
                  'b': 'board-1',
                  'p': 'Idea',
                  'c': '#FEF08A',
                },
              ),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit sticky:color board-1 Idea --color '#FEF08A'",
    );
  });

  test(
    'executor can preview play command without file when playlist panel auto-resolves',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke(
                  'yoloit_play',
                  <String, Object?>{},
                  runtimeContext: const ChatRuntimeContext(
                    boardId: 'board-1',
                    panelId: 'panel-chat',
                    panelType: 'board.chat',
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(result['ok'], true);
      expect(result['command'], 'yoloit play');
    },
  );

  test('executor keeps note:create board/title argument order', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke(
                'ncrt',
                <String, Object?>{'title': 'milk'},
                runtimeContext: const ChatRuntimeContext(boardId: 'board-1'),
              ),
            )
            as Map<String, Object?>;
    expect(result['ok'], isTrue);
    expect(result['executed'], isFalse);
    expect(result['command'], 'yoloit note:create milk');
  });

  test(
    'executor resolves tools/yoloit when launched from nested app cwd',
    () async {
      final originalCwd = Directory.current;
      final nested = Directory(
        '${originalCwd.path}/build/macos/Build/Products/Debug/'
        'YoLoIT (dev).app/Contents/MacOS',
      )..createSync(recursive: true);
      addTearDown(() => Directory.current = originalCwd);

      Directory.current = nested;
      final result =
          jsonDecode(
                await YoloitCliToolExecutor().invoke(
                  'yoloit_help',
                  const <String, Object?>{},
                ),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(result['command'], 'yoloit help');
      expect(result['stdout'], isA<String>());
    },
  );

  test('argument normalizer infers omitted panel type from user message', () {
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_create',
        arguments: const <String, Object?>{'title': 'Release Kanban'},
        userMessage: 'Create a kanban panel named Release Kanban.',
      ),
      containsPair('type', 'board.kanban'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_create',
        arguments: const <String, Object?>{'title': 'Dev Server'},
        userMessage: 'Create a Run panel titled Dev Server.',
      ),
      containsPair('type', 'board.run'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_create',
        arguments: const <String, Object?>{},
        userMessage: 'Сделай заметку на текущей доске.',
      ),
      allOf(
        containsPair('type', 'board.note.markdown'),
        containsPair('title', 'Note'),
      ),
    );
  });

  test('argument normalizer infers help format from user message', () {
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_help',
        arguments: const <String, Object?>{},
        userMessage: 'Show detailed YoLoIT CLI help.',
      ),
      containsPair('format', 'detailed'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_help',
        arguments: const <String, Object?>{},
        userMessage: 'Show the tools help output.',
      ),
      containsPair('format', 'tools'),
    );
  });

  test('argument normalizer fills obvious board arguments from user message', () {
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_board_zoom',
        arguments: const <String, Object?>{},
        userMessage: 'Set the current board zoom to 1.25.',
      ),
      containsPair('scale', 1.25),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_board_arrange',
        arguments: const <String, Object?>{},
        userMessage:
            'Arrange panels to the right with horizontal spacing 40 and vertical spacing 30.',
      ),
      allOf(
        containsPair('direction', 'right'),
        containsPair('h_spacing', 40),
        containsPair('v_spacing', 30),
      ),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_board_translate',
        arguments: const <String, Object?>{},
        userMessage: 'Move the board viewport to x 120 and y -80.',
      ),
      allOf(containsPair('x', 120), containsPair('y', -80)),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_board_delete',
        arguments: const <String, Object?>{},
        userMessage:
            'Delete board Scratch Board; I confirm this destructive action.',
      ),
      allOf(
        containsPair('id_or_name', 'Scratch Board'),
        containsPair('confirm', true),
      ),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'bgt',
        arguments: const <String, Object?>{'b': 'current board'},
        userMessage: 'Show details for the current board.',
        runtimeContext: const ChatRuntimeContext(boardId: 'board-main'),
      ),
      containsPair('id_or_name', 'board-main'),
    );
  });

  test('argument normalizer fills obvious panel arguments from user message', () {
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_panel_help',
        userMessage: 'Show details and content for the current panel.',
      ),
      'yoloit_panel',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_board_focus',
        userMessage: 'Focus the panel named Builds on this board.',
      ),
      'yoloit_panel_focus',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_note_create',
        userMessage:
            'On the current board, create a markdown note panel titled Architecture Notes.',
      ),
      'yoloit_panel_create',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_note_create',
        userMessage: 'Сделай заметку купить молоко.',
      ),
      'yoloit_note_create',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_panel',
        userMessage: 'Сделай фокус на заметку с mermaid диаграммой.',
      ),
      'yoloit_panel_focus',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_board_use',
        userMessage: 'перейди на music борд',
      ),
      'yoloit_board_focus',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_board_use',
        userMessage: 'Переди на таспорт.',
      ),
      'yoloit_board_focus',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_move',
        arguments: const <String, Object?>{},
        userMessage: 'Move the current panel to x 300 and y 180.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(
        containsPair('panel', 'panel-chat'),
        containsPair('x', 300),
        containsPair('y', 180),
      ),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_resize',
        arguments: const <String, Object?>{},
        userMessage: 'Resize the current panel to width 640 and height 420.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(
        containsPair('panel', 'panel-chat'),
        containsPair('width', 640),
        containsPair('height', 420),
      ),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_resize',
        arguments: const <String, Object?>{},
        userMessage: 'Увеличь ее размер.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(containsPair('width', 500), containsPair('height', 400)),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_resize',
        arguments: const <String, Object?>{},
        userMessage: 'Увеличь панель до 700x520.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(containsPair('width', 700), containsPair('height', 520)),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_resize',
        arguments: const <String, Object?>{},
        userMessage: 'Увеличь панель до desktop.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(containsPair('width', 1200), containsPair('height', 800)),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_resize',
        arguments: const <String, Object?>{},
        userMessage: 'Set panel to mobile size.',
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      allOf(containsPair('width', 390), containsPair('height', 844)),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_focus',
        arguments: const <String, Object?>{'panel': 'panel-chat'},
        userMessage: 'Сделай фокус на заметку с mermaid диаграммой.',
        runtimeContext: const ChatRuntimeContext(
          panelId: 'panel-chat',
          panelTitle: '__SMOKE_CHAT__',
        ),
      ),
      containsPair('panel', 'mermaid'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_focus',
        arguments: const <String, Object?>{'panel': 'p-1779529932268'},
        userMessage: 'Сделай фокус на заметку с mermaid диаграммой.',
        runtimeContext: const ChatRuntimeContext(
          panelId: '__SMOKE_CHAT__',
          panelTitle: '__SMOKE_CHAT__',
        ),
      ),
      containsPair('panel', 'mermaid'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_create',
        arguments: const <String, Object?>{},
        userMessage:
            'On the current board, create a markdown note panel titled Architecture Notes.',
      ),
      containsPair('title', 'Architecture Notes'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_panel_delete',
        arguments: const <String, Object?>{},
        userMessage:
            'Delete panel Scratch Panel on this board; I confirm this destructive action.',
      ),
      allOf(
        containsPair('panel', 'Scratch Panel'),
        containsPair('confirm', true),
      ),
    );
  });

  test('argument normalizer handles misc board tool drift', () {
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_reload',
        userMessage: 'Hot restart the app now.',
      ),
      'yoloit_restart',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalizeFunctionName(
        functionName: 'yoloit_note_replace',
        userMessage: "Replace the current note content with '# Launch Notes'.",
      ),
      'yoloit_note',
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_note_append',
        arguments: const <String, Object?>{'panel': 'panel_chat'},
        userMessage:
            "Append '- verify microphone permissions' to the current note panel.",
        runtimeContext: const ChatRuntimeContext(panelId: 'panel-chat'),
      ),
      containsPair('panel', 'panel-chat'),
    );
    expect(
      YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'yoloit_link_delete',
        arguments: const <String, Object?>{},
        userMessage:
            'Delete link link-42 from this board; I confirm this destructive action.',
      ),
      allOf(containsPair('link_id', 'link-42'), containsPair('confirm', true)),
    );
  });

  test('executor blocks destructive commands without confirmation', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke('yoloit_board_delete', <String, Object?>{
                'id_or_name': 'Scratch',
              }),
            )
            as Map<String, Object?>;

    expect(result['ok'], isFalse);
    expect(result['executed'], isFalse);
    expect(result['error'], contains('requires confirm=true'));
  });

  test('local chat emits UI tool events when model calls a CLI tool', () async {
    final tmp = Directory.systemTemp.createTempSync('yoloit-local-tools-test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final engine = _PromptToolEngine(
      decisions: <_ToolDecision>[
        const _ToolDecision(
          promptNeedle: 'create a board',
          functionName: 'yoloit_board_create',
          args: <String, Object?>{'name': 'Sprint'},
        ),
      ],
    );
    final provider = LocalLlmProvider(
      engine: engine,
      installedModelLoader: () async => _installedModel(tmp),
      toolExecutor: YoloitCliToolExecutor(execute: false),
    );

    final events =
        await provider
            .sendMessage(
              message: 'create a board named Sprint',
              config: _config(),
              isFirstMessage: true,
              runtimeContext: const ChatRuntimeContext(
                boardId: 'current-board',
                boardName: 'Main',
                panelId: 'chat-panel',
                panelTitle: 'YoLo Chat',
              ),
            )
            .toList();

    expect(
      engine.requests.single.tools.map((t) => t.name),
      contains('bmk'), // board:create alias
    );
    final requestText = _requestText(engine.requests.single);
    expect(requestText, contains('YoLoIT chat UI assistant'));
    expect(requestText, contains('Board id: current-board'));
    expect(
      events.where((e) => e.type == ChatEventType.toolStart).single.toolName,
      'board:create',
    );
    final complete =
        events.where((e) => e.type == ChatEventType.toolComplete).single;
    expect(complete.toolSuccess, isTrue);
    expect(complete.toolResultContent, contains('yoloit board:create Sprint'));
  });

  test(
    'local chat applies compact routing profile for tiny qwen router runs',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'yoloit-local-fast-route',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final engine = _SequentialToolEngine([
        (request, onChunk) async {
          expect(request.maxTokens, 128);
          expect(request.temperature, 0.0);
          expect(request.enableThinking, isFalse);
          final prompt = _requestText(request);
          expect(prompt, contains('YoLo Assistant router'));
          expect(prompt, isNot(contains('chat UI assistant')));
          const response = 'Routing complete.';
          onChunk(response);
          return response;
        },
      ]);
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader:
            () async => _installedModel(tmp, _qwenTinyManifest),
        toolExecutor: YoloitCliToolExecutor(execute: false),
      );

      await provider
          .sendMessage(
            message: 'show detailed cli help',
            config: _config(
              model: _qwenTinyManifest.id,
              sessionName: 'fast-route',
            ),
            isFirstMessage: true,
            runtimeContext: const ChatRuntimeContext(
              boardId: 'board-1',
              panelId: 'chat-panel',
            ),
          )
          .toList();
    },
  );

  test('local chat executes router JSON fallback tool call', () async {
    final tmp = Directory.systemTemp.createTempSync('yoloit-local-router-json');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final engine = _SequentialToolEngine([
      (request, onChunk) async {
        const response = '{"name":"bmk","arguments":{"n":"Sprint"}}';
        onChunk(response);
        return response;
      },
    ]);
    final provider = LocalLlmProvider(
      engine: engine,
      installedModelLoader: () async => _installedModel(tmp, _qwenTinyManifest),
      toolExecutor: YoloitCliToolExecutor(execute: false),
    );

    final events =
        await provider
            .sendMessage(
              message: 'create a board named Sprint',
              config: _config(
                model: _qwenTinyManifest.id,
                sessionName: 'router-json',
              ),
              isFirstMessage: true,
              runtimeContext: const ChatRuntimeContext(boardId: 'board-1'),
            )
            .toList();

    expect(
      events.where((e) => e.type == ChatEventType.toolStart).single.toolName,
      'board:create',
    );
    expect(
      events
          .where((e) => e.type == ChatEventType.toolComplete)
          .single
          .toolResultContent,
      contains('yoloit board:create Sprint'),
    );
  });

  test(
    'local chat detects different requested CLI tool categories without UI',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'yoloit-local-tools-batch-test',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final cases = <({String text, _ToolDecision decision, String command})>[
        (
          text: 'create a board called Launch',
          decision: const _ToolDecision(
            promptNeedle: 'create a board',
            functionName: 'yoloit_board_create',
            args: <String, Object?>{'name': 'Launch'},
          ),
          command: 'board:create',
        ),
        (
          text: 'create a note panel titled Plan',
          decision: const _ToolDecision(
            promptNeedle: 'note panel',
            functionName: 'yoloit_panel_create',
            args: <String, Object?>{
              'type': 'board.note.markdown',
              'title': 'Plan',
            },
          ),
          command: 'panel:create',
        ),
        (
          text: 'append a checklist to the current note',
          decision: const _ToolDecision(
            promptNeedle: 'append',
            functionName: 'yoloit_note_append',
            args: <String, Object?>{'text': '- Ship microphone fix'},
          ),
          command: 'note:append',
        ),
        (
          text: 'add a kanban card to Todo',
          decision: const _ToolDecision(
            promptNeedle: 'kanban',
            functionName: 'yoloit_kanban_add_card',
            args: <String, Object?>{
              'column': 'Todo',
              'title': 'Fix permissions',
            },
          ),
          command: 'kanban:add-card',
        ),
        (
          text: 'show run configs for this panel',
          decision: const _ToolDecision(
            promptNeedle: 'run configs',
            functionName: 'yoloit_run_list',
            args: <String, Object?>{},
          ),
          command: 'run:list',
        ),
      ];

      for (final item in cases) {
        final engine = _PromptToolEngine(
          decisions: <_ToolDecision>[item.decision],
        );
        final provider = LocalLlmProvider(
          engine: engine,
          installedModelLoader: () async => _installedModel(tmp),
          toolExecutor: YoloitCliToolExecutor(execute: false),
        );

        final events =
            await provider
                .sendMessage(
                  message: item.text,
                  config: _config(sessionName: item.command),
                  isFirstMessage: true,
                  runtimeContext: const ChatRuntimeContext(
                    boardId: 'board-1',
                    panelId: 'panel-1',
                  ),
                )
                .toList();

        expect(
          events
              .where((e) => e.type == ChatEventType.toolStart)
              .single
              .toolName,
          item.command,
          reason: item.text,
        );
      }
    },
  );

  test(
    'local chat filters disabled tools from model request and blocks drift',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'yoloit-local-disabled-tools-test',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final engine = _PromptToolEngine(
        decisions: <_ToolDecision>[
          const _ToolDecision(
            promptNeedle: 'delete board',
            functionName: 'bdl', // board:delete alias
            args: <String, Object?>{'b': 'Scratch', 'cf': true},
          ),
        ],
      );
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _installedModel(tmp),
        toolExecutor: YoloitCliToolExecutor(execute: false),
      );

      final events =
          await provider
              .sendMessage(
                message: 'delete board Scratch, I confirm',
                config: _config(disabledLocalToolNames: const <String>{'bdl'}),
                isFirstMessage: true,
                runtimeContext: const ChatRuntimeContext(boardId: 'board-1'),
              )
              .toList();

      expect(
        engine.requests.single.tools.map((tool) => tool.name),
        isNot(contains('bdl')), // board:delete alias
      );
      final complete =
          events
              .where((event) => event.type == ChatEventType.toolComplete)
              .single;
      expect(complete.toolSuccess, isFalse);
      expect(complete.toolResultContent, contains('disabled'));
    },
  );

  test(
    'local chat includes prior chat and tool calls in the next prompt',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'yoloit-local-tool-history-test',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final engine = _SequentialToolEngine(<_ScriptedCompletion>[
        (request, onChunk) async {
          final result = await request.onToolCall!(
            'yoloit_panel_create',
            const <String, Object?>{
              'type': 'board.note.markdown',
              'title': 'Plan',
            },
          );
          final response = 'Created note: $result';
          onChunk(response);
          return response;
        },
        (request, onChunk) async {
          final prompt = _requestText(request).toLowerCase();
          expect(prompt, contains('create a note panel titled plan'));
          expect(prompt, contains('assistant: created note:'));
          expect(prompt, contains('tool call history:'));
          expect(prompt, contains('panel:create'));
          expect(prompt, contains('board.note.markdown'));
          expect(prompt, contains('plan'));
          const response = 'I remember the note tool call.';
          onChunk(response);
          return response;
        },
      ]);
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _installedModel(tmp),
        toolExecutor: YoloitCliToolExecutor(execute: false),
      );
      final config = _config(sessionName: 'tool-history');

      await provider
          .sendMessage(
            message: 'create a note panel titled Plan',
            config: config,
            isFirstMessage: true,
            runtimeContext: const ChatRuntimeContext(
              boardId: 'board-1',
              panelId: 'chat-panel',
            ),
          )
          .toList();
      await provider
          .sendMessage(
            message: 'what did you just create?',
            config: config,
            isFirstMessage: false,
            runtimeContext: const ChatRuntimeContext(
              boardId: 'board-1',
              panelId: 'chat-panel',
            ),
          )
          .toList();

      expect(engine.requests, hasLength(2));
    },
  );
}

flm.InstalledModel _installedModel(
  Directory dir, [
  flm.LocalModelManifest manifest = _manifest,
]) {
  return flm.InstalledModel(
    manifest: manifest,
    directory: dir,
    sourceLabel: 'test',
    installedAt: DateTime.now(),
    sizeBytes: 1,
  );
}

ChatSessionConfig _config({
  String sessionName = 'local-test',
  String model = 'test-local-chat-tools',
  Set<String> disabledLocalToolNames = const <String>{},
}) {
  return ChatSessionConfig(
    sessionName: sessionName,
    workingDir: Directory.current.path,
    provider: 'local',
    model: model,
    disabledLocalToolNames: disabledLocalToolNames.toList(),
  );
}

class _ToolDecision {
  const _ToolDecision({
    required this.promptNeedle,
    required this.functionName,
    required this.args,
  });

  final String promptNeedle;
  final String functionName;
  final Map<String, Object?> args;
}

String _requestText(flm.LmCompletionRequest request) {
  if (request.prompt.trim().isNotEmpty) {
    return request.prompt;
  }
  final messages = request.messages;
  if (messages == null || messages.isEmpty) return '';
  return messages
      .map((m) => '${m['role'] ?? ''}: ${m['content'] ?? ''}')
      .join('\n');
}

final class _PromptToolEngine implements flm.LmEngine {
  _PromptToolEngine({required this.decisions});

  final List<_ToolDecision> decisions;
  final List<flm.LmCompletionRequest> requests = <flm.LmCompletionRequest>[];

  @override
  Future<String> complete(flm.LmCompletionRequest request) {
    throw UnimplementedError('complete is not used by these tests');
  }

  @override
  Future<String> completeStreaming(
    flm.LmCompletionRequest request,
    void Function(String chunk) onChunk,
  ) async {
    requests.add(request);
    expect(request.tools, isNotEmpty);
    expect(request.onToolCall, isNotNull);
    final prompt = _requestText(request).toLowerCase();
    final decision = decisions.singleWhere(
      (candidate) => prompt.contains(candidate.promptNeedle),
      orElse:
          () =>
              throw StateError(
                'No tool decision matched prompt: ${_requestText(request)}',
              ),
    );
    final result = await request.onToolCall!(
      decision.functionName,
      decision.args,
    );
    final response = 'Called ${decision.functionName}: $result';
    onChunk(response);
    return response;
  }
}

typedef _ScriptedCompletion =
    Future<String> Function(
      flm.LmCompletionRequest request,
      void Function(String chunk) onChunk,
    );

final class _SequentialToolEngine implements flm.LmEngine {
  _SequentialToolEngine(this.completions);

  final List<_ScriptedCompletion> completions;
  final List<flm.LmCompletionRequest> requests = <flm.LmCompletionRequest>[];
  int _index = 0;

  @override
  Future<String> complete(flm.LmCompletionRequest request) {
    throw UnimplementedError('complete is not used by these tests');
  }

  @override
  Future<String> completeStreaming(
    flm.LmCompletionRequest request,
    void Function(String chunk) onChunk,
  ) {
    requests.add(request);
    expect(request.tools, isNotEmpty);
    expect(request.onToolCall, isNotNull);
    return completions[_index++](request, onChunk);
  }
}
