import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/hotkeys/hotkeys.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

/// Records [onTerminalEnterPressed] calls without touching real session state.
class _RecordingTerminalCubit extends TerminalCubit {
  final List<String> enterPressed = [];

  @override
  void onTerminalEnterPressed(String sessionId) {
    enterPressed.add(sessionId);
  }
}

Future<void> _pressCmd(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory clipboard: unhandled platform messages get no reply in widget
  // tests, which would hang Clipboard.setData/getData futures forever.
  String? clipboardText;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
    AgentConfigService.instance.setTerminalRenderEngineForTesting(
      TerminalRenderEngine.xterm,
    );
  });

  Future<(GlobalKey<TerminalWidgetState>, AgentSession)> pumpTerminal(
    WidgetTester tester, {
    List<String>? outputs,
    AgentSession? session,
    TerminalCubit? cubit,
  }) async {
    final key = GlobalKey<TerminalWidgetState>();
    final effectiveSession =
        session ??
        AgentSession(
          id: 'sess_keys',
          type: AgentType.copilot,
          workspacePath: '/project',
        );
    final terminal = TerminalWidget(
      key: key,
      session: effectiveSession,
      isActive: true,
      terminalOutputWriter: (_, data) => outputs?.add(data),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 200,
            child: cubit == null
                ? terminal
                : BlocProvider<TerminalCubit>.value(
                    value: cubit,
                    child: terminal,
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (key, effectiveSession);
  }

  group('hardware shortcut actions', () {
    testWidgets('Cmd+= increases and Cmd+- decreases the font size', (
      tester,
    ) async {
      final (key, _) = await pumpTerminal(tester);
      expect(key.currentState!.currentFontSize, 13.0);

      await _pressCmd(tester, LogicalKeyboardKey.equal);
      expect(key.currentState!.currentFontSize, 14.0);

      await _pressCmd(tester, LogicalKeyboardKey.minus);
      expect(key.currentState!.currentFontSize, 13.0);
    });

    testWidgets('font size shortcuts clamp at the lower bound', (tester) async {
      final (key, _) = await pumpTerminal(tester);

      for (var i = 0; i < 10; i++) {
        await _pressCmd(tester, LogicalKeyboardKey.minus);
      }
      expect(key.currentState!.currentFontSize, 8.0);
    });

    testWidgets('font size shortcuts clamp at the upper bound', (tester) async {
      final (key, _) = await pumpTerminal(tester);

      for (var i = 0; i < 30; i++) {
        await _pressCmd(tester, LogicalKeyboardKey.equal);
      }
      expect(key.currentState!.currentFontSize, 32.0);
    });

    testWidgets('shortcuts are ignored when the terminal is not focused', (
      tester,
    ) async {
      final key = GlobalKey<TerminalWidgetState>();
      final session = AgentSession(
        id: 'sess_unfocused',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              // isActive: false + autoRequestFocus: false keeps the terminal
              // unfocused (TerminalView autofocuses when active), so the
              // hardware key handler must ignore the shortcut.
              child: TerminalWidget(
                key: key,
                session: session,
                isActive: false,
                autoRequestFocus: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _pressCmd(tester, LogicalKeyboardKey.equal);
      expect(key.currentState!.currentFontSize, 13.0);
    });

    testWidgets('Cmd+A selects the whole terminal buffer', (tester) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('select me\r\n');
      await tester.pump();

      expect(
        tester.widget<TerminalView>(find.byType(TerminalView)).controller?.selection,
        isNull,
      );

      await _pressCmd(tester, LogicalKeyboardKey.keyA);
      expect(
        tester.widget<TerminalView>(find.byType(TerminalView)).controller?.selection,
        isNotNull,
      );
    });

    testWidgets('Cmd+C with a selection copies buffer text to the clipboard', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('hello-clipboard\r\n');
      await tester.pump();

      await _pressCmd(tester, LogicalKeyboardKey.keyA);
      await _pressCmd(tester, LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(clipboardText, contains('hello-clipboard'));
    });

    testWidgets('Cmd+F opens the search overlay', (tester) async {
      await pumpTerminal(tester);
      expect(find.text('Find in terminal…'), findsNothing);

      await _pressCmd(tester, LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(find.text('Find in terminal…'), findsOneWidget);
    });

    testWidgets('Cmd+V paste shortcut is handled without crashing', (
      tester,
    ) async {
      final (key, _) = await pumpTerminal(tester);
      await Clipboard.setData(const ClipboardData(text: 'echo hello'));

      await _pressCmd(tester, LogicalKeyboardKey.keyV);
      // Let the async smart-paste pipeline complete against the fake backend.
      await tester.pump(const Duration(milliseconds: 200));

      expect(key.currentState!.currentFontSize, 13.0);
    });

    testWidgets('Cmd+O invokes the app-level file search action', (
      tester,
    ) async {
      var fileSearchInvoked = 0;
      final session = AgentSession(
        id: 'sess_file_search',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  OpenFileSearchIntent: CallbackAction<OpenFileSearchIntent>(
                    onInvoke: (intent) {
                      fileSearchInvoked++;
                      return null;
                    },
                  ),
                },
                child: TerminalWidget(session: session, isActive: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _pressCmd(tester, LogicalKeyboardKey.keyO);

      expect(fileSearchInvoked, 1);
    });
  });

  group('terminal focus key handling', () {
    testWidgets('Shift+Enter is consumed and not forwarded to the PTY', (
      tester,
    ) async {
      final outputs = <String>[];
      await pumpTerminal(tester, outputs: outputs);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(outputs, isEmpty);
    });

    testWidgets('plain Enter while awaiting approval notifies the cubit', (
      tester,
    ) async {
      final cubit = _RecordingTerminalCubit();
      final session = AgentSession(
        id: 'sess_approval',
        type: AgentType.copilot,
        workspacePath: '/project',
        hookPhase: const AwaitingApprovalPhase(),
      );
      await pumpTerminal(tester, session: session, cubit: cubit);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(cubit.enterPressed, ['sess_approval']);
    });

    testWidgets('plain Enter without approval is left to the terminal', (
      tester,
    ) async {
      final cubit = _RecordingTerminalCubit();
      final session = AgentSession(
        id: 'sess_plain_enter',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      await pumpTerminal(tester, session: session, cubit: cubit);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(cubit.enterPressed, isEmpty);
    });
  });
}
