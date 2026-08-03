import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plugin = YoloAssistantPlugin();

  test('typeId is board.yolo_assistant', () {
    expect(plugin.typeId, 'board.yolo_assistant');
    expect(YoloAssistantPluginBase.kTypeId, 'board.yolo_assistant');
  });

  test('displayName is YoLo Assistant', () {
    expect(plugin.displayName, 'YoLo Assistant');
  });

  test('icon is smart_toy', () {
    expect(plugin.icon, Icons.auto_awesome);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, const Color(0xFF8B5CF6));
  });

  test('defaultSize is 420x560', () {
    expect(plugin.defaultSize, const Size(420, 560));
  });

  test('hasEditor is false', () {
    expect(plugin.hasEditor, isFalse);
  });

  test('initialState has expected keys', () {
    final state = plugin.initialState;
    expect(state.containsKey('messages'), isTrue);
    expect(state.containsKey('activeSkills'), isTrue);
    expect(state.containsKey('mode'), isTrue);
    expect(state.containsKey('isListening'), isTrue);
    expect(state.containsKey('isSpeaking'), isTrue);
    expect(state['messages'], <Map<String, dynamic>>[]);
    expect(state['activeSkills'], ['Terminal', 'Board Control', 'Web Search']);
    expect(state['mode'], 'text');
    expect(state['isListening'], false);
    expect(state['isSpeaking'], false);
  });

  group('YoloAssistantWidget', () {
    const recordChannel = MethodChannel('com.llfbandit.record/messages');
    const micChannel = MethodChannel('yoloit/microphone_permission');

    late BoardCubit cubit;
    late Map<String, dynamic> panelState;
    String? clipboardText;
    bool micGranted = false;

    BoardPanelInstance buildPanel() {
      return BoardPanelInstance(
        id: 'assistant-1',
        type: YoloAssistantPluginBase.kTypeId,
        title: 'YoLo Assistant',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 560),
        state: panelState,
      );
    }

    Future<void> pumpAssistant(WidgetTester tester) async {
      // Give the panel room so menus/sheets don't overflow the test surface.
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final panel = buildPanel();
      final board = BoardDocument(
        id: 'board-1',
        name: 'Test board',
        viewport: const BoardViewport(scale: 1),
        panels: [panel],
      );
      cubit.emit(
        BoardState(boards: [board], activeBoardId: 'board-1', isLoaded: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: YoloAssistantWidget(
                panel: panel,
                onUpdateState: (next) {
                  panelState = next;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      cubit = BoardCubit();      panelState = <String, dynamic>{
        'messages': <Map<String, dynamic>>[],
        'activeSkills': ['Terminal', 'Board Control', 'Web Search'],
        'mode': 'text',
      };
      clipboardText = null;
      micGranted = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(recordChannel, (call) async {
        switch (call.method) {
          case 'hasPermission':
            return true;
          case 'isRecording':
          case 'isPaused':
            return false;
          default:
            return null;
        }
      });
      messenger.setMockMethodCallHandler(micChannel, (call) async {
        switch (call.method) {
          case 'request':
            return micGranted;
          case 'displayName':
            return 'YoLoIT Test';
          case 'bundleIdentifier':
            return 'com.yoloit.test';
          case 'status':
            return 'denied';
          case 'openSettings':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(recordChannel, null);
      messenger.setMockMethodCallHandler(micChannel, null);
    });

    List<Map<String, dynamic>> sampleMessages() => [
      {
        'id': 'u1',
        'role': 'user',
        'content': 'Hello YoLo',
        'timestamp': '2026-08-01T10:00:00.000Z',
      },
      {
        'id': 'u2',
        'role': 'user',
        'content': '[Voice message]\ntake out the trash',
        'timestamp': '2026-08-01T10:01:00.000Z',
      },
      {
        'id': 'a1',
        'role': 'assistant',
        'content': 'Here is the answer',
        'timestamp': '2026-08-01T10:02:00.000Z',
      },
      {
        'id': 't1',
        'role': 'tool',
        'toolName': 'panels',
        'content': 'yoloit panels board-1',
        'rawResult': '{"ok": true}',
        'arguments': {'board': 'board-1'},
        'success': true,
        'timestamp': '2026-08-01T10:03:00.000Z',
      },
      {
        'id': 't2',
        'role': 'tool',
        'toolName': 'note:write',
        'content': 'Tool failed: panel not found',
        'rawResult': '{"ok": false, "error": "panel not found"}',
        'arguments': {'panel': 'nope'},
        'success': false,
        'timestamp': '2026-08-01T10:04:00.000Z',
      },
    ];

    testWidgets('renders user, voice, assistant and tool message bubbles', (
      tester,
    ) async {
      panelState['messages'] = sampleMessages();
      await pumpAssistant(tester);

      // Plain user message rendered as-is.
      expect(find.text('Hello YoLo'), findsOneWidget);
      // Voice prefix is stripped from the visible user bubble.
      expect(find.text('take out the trash'), findsOneWidget);
      expect(find.textContaining('[Voice message'), findsNothing);
      // Assistant message renders through the markdown body.
      expect(find.byType(MarkdownBody), findsOneWidget);
      // Successful tool bubble shows tool name and compact result.
      expect(find.textContaining('panels'), findsWidgets);
      expect(find.textContaining('yoloit panels board-1'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);
      // Failed tool bubble uses the error icon and failure text.
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.textContaining('Tool failed: panel not found'), findsOneWidget);
      // Session bar shows the message count.
      expect(find.text('5 msgs'), findsOneWidget);
    });

    testWidgets('shows empty-state hint when there are no messages', (
      tester,
    ) async {
      await pumpAssistant(tester);
      expect(find.text('Send a message to start'), findsOneWidget);
      expect(find.text('0 msgs'), findsOneWidget);
    });

    testWidgets('long-press on a message copies it to the clipboard', (
      tester,
    ) async {
      panelState['messages'] = sampleMessages();
      await pumpAssistant(tester);

      // Long-press the assistant bubble (markdown has no own long-press
      // recognizer, so the bubble's GestureDetector handles it).
      await tester.longPress(
        find.text('Here is the answer', findRichText: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(clipboardText, 'Here is the answer');
      expect(find.text('Copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('copy chat log menu action copies full log to clipboard', (
      tester,
    ) async {
      panelState['messages'] = sampleMessages();
      await pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy chat log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('=== YoLoIT Chat Logs ==='));
      expect(clipboardText, contains('Messages: 5'));
      expect(clipboardText, contains('--- [user] ---'));
      expect(clipboardText, contains('Hello YoLo'));
      expect(clipboardText, isNot(contains('=== LLM Debug Sessions ===')));
      expect(
        find.text('Full chat log copied to clipboard'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('simulated debug session is included in the copied log', (
      tester,
    ) async {
      panelState['messages'] = sampleMessages();
      await pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LLM debug logs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simulate'));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy chat log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(clipboardText, contains('=== LLM Debug Sessions ==='));
      expect(
        clipboardText,
        contains('User: [Simulation] Show weather + open browser'),
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('clear chat empties the message list', (tester) async {
      panelState['messages'] = sampleMessages();
      await pumpAssistant(tester);

      await tester.tap(find.byTooltip('Clear chat'));
      await tester.pump();

      expect(panelState['messages'], isEmpty);
    });

    testWidgets('microphone permission hint appears when macOS denies access', (
      tester,
    ) async {
      await pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Microphone access required'), findsOneWidget);
      expect(find.textContaining('com.yoloit.test'), findsOneWidget);
      expect(
        find.textContaining('tccutil reset Microphone com.yoloit.test'),
        findsOneWidget,
      );

      // Requesting again while still denied shows a snackbar.
      await tester.tap(find.text('Request again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Microphone is still not allowed by macOS'),
        findsOneWidget,
      );
      // Let the snackbar expire before the next interaction.
      await tester.pump(const Duration(seconds: 3));

      // Copy reset command puts the tccutil command on the clipboard.
      await tester.tap(find.text('Copy reset command'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(clipboardText, 'tccutil reset Microphone com.yoloit.test');
      expect(find.text('Copied reset command'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      // Open settings routes through the permission service (mocked true).
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Microphone access required'), findsNothing);
    });

    testWidgets('request again closes the dialog once access is granted', (
      tester,
    ) async {
      await pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Microphone access required'), findsOneWidget);

      micGranted = true;
      await tester.tap(find.text('Request again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Microphone access required'), findsNothing);
    });

    testWidgets('voice mode toggle switches UI and back', (tester) async {
      await pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.graphic_eq));
      await tester.pump();
      expect(panelState['mode'], 'voice');

      // Rebuild with the updated (voice) state.
      await pumpAssistant(tester);
      expect(find.text('Tap to speak'), findsOneWidget);
      expect(find.text('Back to text'), findsOneWidget);
      // Skills bar is visible in voice mode.
      expect(find.text('Terminal'), findsOneWidget);

      await tester.tap(find.text('Back to text'));
      await tester.pump();
      expect(panelState['mode'], 'text');
    });

    testWidgets('add skill sheet adds a skill in voice mode', (tester) async {
      panelState['mode'] = 'voice';
      await pumpAssistant(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add Skill'), findsOneWidget);

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(panelState['activeSkills'], contains('Notes'));
    });

    testWidgets('removing a skill chip updates active skills', (tester) async {
      panelState['mode'] = 'voice';
      await pumpAssistant(tester);

      final chip = find.widgetWithText(InputChip, 'Terminal');
      expect(chip, findsOneWidget);
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.close)),
      );
      await tester.pump();

      expect(panelState['activeSkills'], isNot(contains('Terminal')));
    });
  });
}
