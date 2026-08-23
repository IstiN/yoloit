import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // In-memory clipboard: unhandled platform messages get no reply in
    // widget tests, which would hang Clipboard.setData/getData futures.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': null};
          }
          return null;
        });
    AgentConfigService.instance.setTerminalRenderEngineForTesting(
      TerminalRenderEngine.xterm,
    );
  });

  Future<(GlobalKey<TerminalWidgetState>, AgentSession)> pumpTerminal(
    WidgetTester tester, {
    double width = 600,
    double height = 200,
  }) async {
    final key = GlobalKey<TerminalWidgetState>();
    final session = AgentSession(
      id: 'sess_menu',
      type: AgentType.copilot,
      workspacePath: '/project',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: TerminalWidget(
              key: key,
              session: session,
              isActive: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (key, session);
  }

  TerminalController? terminalController(WidgetTester tester) {
    return tester
        .widget<TerminalView>(find.byType(TerminalView))
        .controller;
  }

  Future<void> openContextMenu(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(TerminalView));
    await tester.tapAt(center, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  group('terminal context menu', () {
    testWidgets('secondary click shows base menu without selection entries', (
      tester,
    ) async {
      await pumpTerminal(tester);

      await openContextMenu(tester);

      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Find'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Clear selection'), findsNothing);
    });

    testWidgets('Select All selects the buffer and enables Copy entry', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('menu select all\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      expect(terminalController(tester)?.selection, isNotNull);

      await openContextMenu(tester);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Clear selection'), findsOneWidget);
    });

    testWidgets('Clear selection entry removes the selection', (tester) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('menu clear\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();
      expect(terminalController(tester)?.selection, isNotNull);

      await openContextMenu(tester);
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();

      expect(terminalController(tester)?.selection, isNull);
    });

    testWidgets('Copy entry copies the selection and clears it', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('menu copy text\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      await openContextMenu(tester);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(terminalController(tester)?.selection, isNull);
    });

    testWidgets('Find entry opens the search overlay', (tester) async {
      await pumpTerminal(tester);

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();

      expect(find.text('Find in terminal…'), findsOneWidget);
    });
  });

  group('terminal search overlay', () {
    testWidgets('typing a query reports hits and highlights the first one', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('hello world\r\nhello again\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.text('1 of 2'), findsOneWidget);
      expect(terminalController(tester)?.selection, isNotNull);
    });

    testWidgets('next/previous buttons cycle through hits with wrap-around', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('hello world\r\nhello again\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);

      // Wrap around to the first hit.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);

      // Wrap around backwards to the last hit.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('a query without matches shows No results', (tester) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('some content\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pump();

      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('clearing the query clears hits and the selection', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('hello world\r\n');
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(terminalController(tester)?.selection, isNotNull);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(terminalController(tester)?.selection, isNull);
      expect(find.text('No results'), findsNothing);
    });

    testWidgets('hits in the scrollback update the counter only', (
      tester,
    ) async {
      final (_, session) = await pumpTerminal(tester, height: 120);
      session.terminal.write('needle-first-line\r\n');
      for (var i = 0; i < 60; i++) {
        session.terminal.write('filler line $i\r\n');
      }
      await tester.pump();

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'needle-first-line');
      await tester.pump();

      // The hit lives above the visible viewport: counted but not selected.
      expect(find.text('1 of 1'), findsOneWidget);
      expect(terminalController(tester)?.selection, isNull);
    });

    testWidgets('Escape closes the search overlay', (tester) async {
      await pumpTerminal(tester);

      await openContextMenu(tester);
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      expect(find.text('Find in terminal…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('Find in terminal…'), findsNothing);
    });
  });

  group('terminal pointer move selection', () {
    testWidgets('dragging selects terminal text', (tester) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('drag select this line\r\n');
      await tester.pump();

      final rect = tester.getRect(find.byType(TerminalView));
      final gesture = await tester.startGesture(rect.topLeft + const Offset(20, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(terminalController(tester)?.selection, isNotNull);
    });

    testWidgets('a tiny move does not start a selection', (tester) async {
      final (_, session) = await pumpTerminal(tester);
      session.terminal.write('no drag here\r\n');
      await tester.pump();

      final rect = tester.getRect(find.byType(TerminalView));
      final gesture = await tester.startGesture(rect.topLeft + const Offset(20, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(2, 1));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 350));

      expect(terminalController(tester)?.selection, isNull);
    });

    testWidgets('two-finger pinch zoom changes the font size', (tester) async {
      final (key, _) = await pumpTerminal(tester);
      expect(key.currentState!.currentFontSize, 13.0);

      final center = tester.getCenter(find.byType(TerminalView));
      final first = await tester.startGesture(center + const Offset(-40, 0));
      final second = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      expect(key.currentState!.currentFontSize, greaterThan(13.0));

      // Unmount and drain any pending one-shot timers (resize debounce,
      // focus retry) before the binding verifies invariants.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1000));
    });
  });
}
