import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/widgets/chat_setup_view_vm.dart';
import 'package:yoloit/features/board/chat/widgets/model_search_dialog.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// A PlatformDirs that points configDir to a temp directory.
class _TempPlatformDirs extends PlatformDirs {
  _TempPlatformDirs(this._tmpDir);
  final String _tmpDir;

  @override
  String get configDir => _tmpDir;

  @override
  String get dataDir => _tmpDir;

  @override
  String get logsDir => _tmpDir;

  @override
  String get tempDir => _tmpDir;

  @override
  String get skillsDir => '$_tmpDir/skills';

  @override
  String get yoloitTempDir => '$_tmpDir/tmp';
}

const _copilotConfig = AgentConfig(
  id: 'copilot',
  displayName: 'Copilot',
  iconLabel: 'CP',
  launchCommand: '',
  visible: true,
  isBuiltIn: true,
  streamAdapter: 'copilot',
);

const _cursorConfig = AgentConfig(
  id: 'cursor',
  displayName: 'Cursor',
  iconLabel: 'CU',
  launchCommand: '',
  visible: true,
  isBuiltIn: true,
  streamAdapter: 'cursor',
);

const _codexConfig = AgentConfig(
  id: 'codex',
  displayName: 'Codex',
  iconLabel: 'CX',
  launchCommand: '',
  visible: true,
  isBuiltIn: true,
  streamAdapter: 'codex',
  disableModel: true,
);

const _kimiConfig = AgentConfig(
  id: 'kimi',
  displayName: 'Kimi',
  iconLabel: 'K',
  launchCommand: '',
  visible: true,
  isBuiltIn: true,
  streamAdapter: 'kimi',
  disableModel: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splitChatLaunchCommand', () {
    test('splits a plain command on spaces', () {
      expect(
        splitChatLaunchCommand('copilot --flag value'),
        ['copilot', '--flag', 'value'],
      );
    });

    test('collapses consecutive and leading/trailing spaces', () {
      expect(splitChatLaunchCommand('  spaced   out  '), ['spaced', 'out']);
    });

    test('keeps spaces inside double quotes', () {
      expect(
        splitChatLaunchCommand('cmd "arg with space" tail'),
        ['cmd', 'arg with space', 'tail'],
      );
    });

    test('keeps spaces inside single quotes', () {
      expect(
        splitChatLaunchCommand("cmd 'arg with space' tail"),
        ['cmd', 'arg with space', 'tail'],
      );
    });

    test('single quote is literal inside double quotes', () {
      expect(
        splitChatLaunchCommand('cmd "it\'s ok" x'),
        ['cmd', "it's ok", 'x'],
      );
    });

    test('double quote is literal inside single quotes', () {
      expect(
        splitChatLaunchCommand('cmd \'say "hi"\' y'),
        ['cmd', 'say "hi"', 'y'],
      );
    });

    test('unterminated quote consumes the rest of the command', () {
      expect(splitChatLaunchCommand('cmd "unterminated'), [
        'cmd',
        'unterminated',
      ]);
    });

    test('empty input produces no tokens', () {
      expect(splitChatLaunchCommand(''), isEmpty);
      expect(splitChatLaunchCommand('   '), isEmpty);
    });

    test('quoted and unquoted fragments concatenate', () {
      expect(splitChatLaunchCommand('cmd a"b c"d e'), ['cmd', 'ab cd', 'e']);
    });

    test('empty quoted sections are dropped', () {
      expect(splitChatLaunchCommand('cmd "" x'), ['cmd', 'x']);
      expect(splitChatLaunchCommand("cmd last''"), ['cmd', 'last']);
    });
  });

  group('ChatSetupView', () {
    late Directory tmpDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tmpDir = Directory.systemTemp.createTempSync('chat_setup_view_test_');
      PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
      await AgentConfigService.instance.save([
        _copilotConfig,
        _cursorConfig,
        _codexConfig,
        _kimiConfig,
      ]);
    });

    tearDown(() {
      PlatformDirs.setInstance(const MacosPlatformDirs());
      tmpDir.deleteSync(recursive: true);
    });

    Widget buildApp({
      required ChatSessionConfig config,
      List<ChatModelInfo> models = const [],
      ValueChanged<ChatSessionConfig>? onStart,
    }) {
      return BlocProvider<BoardCubit>(
        create: (_) => BoardCubit(),
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
          ),
          home: Scaffold(
            body: ChatSetupView(
              panelId: 'panel-1',
              config: config,
              models: models,
              onStart: onStart ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('normalizes a stale provider to the first available one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'ghost',
              model: 'stale-model',
            ),
          ),
        );
        await tester.pump();

        // 'ghost' is not configured -> falls back to 'copilot' and resets the
        // unknown model to the copilot default.
        expect(find.text('Claude Sonnet 4.6'), findsOneWidget);
      });
    });

    testWidgets('keeps the configured model when it is valid', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'gpt-5-mini',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('GPT-5 mini'), findsOneWidget);
      });
    });

    testWidgets('switching provider resets the model to the new default', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'gpt-5-mini',
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Cursor').last);
        await tester.pump();

        // Model is reset synchronously from the hardcoded cursor list.
        expect(find.text('GPT-5.4 Nano'), findsOneWidget);
      });
    });

    testWidgets('cursor without API key shows the auth hint', (tester) async {
      final envHasKey = Platform.environment.containsKey('CURSOR_API_KEY');
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'cursor',
              model: 'gpt-5.4-nano-medium',
            ),
          ),
        );
        // Let the (I/O-free) key check settle.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }

        expect(
          find.text('Add CURSOR_API_KEY to an env group above to authenticate.'),
          envHasKey ? findsNothing : findsOneWidget,
        );
      });
    });

    testWidgets('cursor with API key in env group loads models and hides hint', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await GlobalEnvGroupsService.instance.saveAll([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Cursor keys',
            values: {'CURSOR_API_KEY': 'test-dummy-key'},
          ),
        ]);

        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'cursor',
              model: 'gpt-5.4-nano-medium',
              envGroupIds: ['g1'],
            ),
          ),
        );
        // Wait for model discovery to finish (loading indicator disappears).
        // `cursor-agent --list-models` either fails fast (not installed) or
        // fails auth with the dummy key; bounded by its own 10s timeout.
        final sw = Stopwatch()..start();
        while (sw.elapsed < const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }

        expect(
          find.text('Add CURSOR_API_KEY to an env group above to authenticate.'),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
      });
    });

    testWidgets('start emits the selected provider, model and paths', (
      tester,
    ) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 'mysess',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'gpt-5-mini',
              envGroupIds: [],
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started, isNotNull);
        expect(started!.provider, 'copilot');
        expect(started!.model, 'gpt-5-mini');
        expect(started!.sessionName, 'mysess');
        expect(started!.workingDir, '/tmp');
        expect(started!.envGroupIds, isEmpty);
      });
    });

    testWidgets('start falls back to the default model when invalid', (
      tester,
    ) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'stale-model',
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started!.model, 'claude-sonnet-4.6');
      });
    });

    testWidgets('disableModel provider hides the selector and emits no model', (
      tester,
    ) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'kimi',
              model: 'kimi-k2.5',
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        expect(find.text('Model'), findsNothing);

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started!.provider, 'kimi');
        expect(started!.model, '');
      });
    });

    testWidgets('codex provider resolves models via the codex adapter', (
      tester,
    ) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'codex',
              model: 'gpt-5.5',
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        // disableModel: the selector is hidden but _start still resolves the
        // codex model list to validate the selection.
        expect(find.text('Model'), findsNothing);

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started!.provider, 'codex');
        expect(started!.model, '');
      });
    });

    testWidgets('empty session name is auto-generated', (tester) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: '',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'gpt-5-mini',
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started!.sessionName, startsWith('chat-'));
      });
    });

    testWidgets('model search dialog updates the selected model', (
      tester,
    ) async {
      ChatSessionConfig? started;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'copilot',
              model: 'gpt-5-mini',
            ),
            onStart: (cfg) => started = cfg,
          ),
        );
        await tester.pump();

        // Open the model search dialog.
        await tester.tap(find.text('GPT-5 mini'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Filter and pick a different model.
        await tester.enterText(
          find.descendant(
            of: find.byType(ModelSearchDialog),
            matching: find.byType(TextField),
          ),
          'opus 4.7',
        );
        await tester.pump();
        await tester.tap(find.text('Claude Opus 4.7'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Claude Opus 4.7'), findsOneWidget);

        await tester.tap(find.text('Start Chat'));
        await tester.pump();

        expect(started!.model, 'claude-opus-4.7');
      });
    });

    testWidgets('missing launch command shows the not-installed banner', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await AgentConfigService.instance.save([
          const AgentConfig(
            id: 'ghost-cli',
            displayName: 'Ghost CLI',
            iconLabel: 'G',
            launchCommand: 'yoloit-missing-cmd-xyz --flag "quoted arg"',
            visible: true,
            isBuiltIn: false,
            streamAdapter: 'copilot',
          ),
        ]);
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'ghost-cli',
              model: 'gpt-5-mini',
            ),
          ),
        );
        // Wait for the availability check (`which` lookup) to settle.
        final sw = Stopwatch()..start();
        while (sw.elapsed < const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('Ghost CLI is not installed').evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.text('Ghost CLI is not installed'), findsOneWidget);
        expect(find.text('Install provider first'), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      });
    });

    testWidgets('installed launch command keeps the start button enabled', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await AgentConfigService.instance.save([
          const AgentConfig(
            id: 'shell-cli',
            displayName: 'Shell CLI',
            iconLabel: 'S',
            launchCommand: 'sh -c "echo hi"',
            visible: true,
            isBuiltIn: false,
            streamAdapter: 'copilot',
          ),
        ]);
        await tester.pumpWidget(
          buildApp(
            config: const ChatSessionConfig(
              sessionName: 's',
              workingDir: '/tmp',
              provider: 'shell-cli',
              model: 'gpt-5-mini',
            ),
          ),
        );
        // Wait for the availability check to resolve to installed.
        final sw = Stopwatch()..start();
        while (sw.elapsed < const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }

        expect(find.text('Shell CLI is not installed'), findsNothing);
        expect(find.text('Start Chat'), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNotNull);
      });
    });

    testWidgets('didUpdateWidget resets an invalid model to the default', (
      tester,
    ) async {
      const config = ChatSessionConfig(
        sessionName: 's',
        workingDir: '/tmp',
        provider: 'copilot',
        model: 'stale-model',
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(buildApp(config: config));
        await tester.pump();
        expect(find.text('stale-model'), findsOneWidget);

        // A different models list identity triggers didUpdateWidget, which
        // revalidates the current selection.
        await tester.pumpWidget(
          buildApp(
            config: config,
            models: const [ChatModelInfo(id: 'x', displayName: 'X')],
          ),
        );
        await tester.pump();

        expect(find.text('Claude Sonnet 4.6'), findsOneWidget);
      });
    });
  });
}
