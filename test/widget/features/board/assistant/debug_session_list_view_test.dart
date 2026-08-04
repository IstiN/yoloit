import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/widgets/debug_session_list_view.dart';

AppColorScheme get _colors =>
    AppThemePreset.neonPurple.theme.extension<AppColorScheme>()!;

Future<void> _pumpView(
  WidgetTester tester,
  List<Map<String, dynamic>> sessions,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: DebugSessionListView(sessions: sessions, colors: _colors),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _detailText(WidgetTester tester) {
  return tester.widget<SelectableText>(find.byType(SelectableText)).data!;
}

Future<void> _selectTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pump();
}

Map<String, dynamic> _richSession() {
  return <String, dynamic>{
    'userMessage': 'refactor the board renderer pipeline',
    'modelId': 'qwen3-32b',
    'modelProvider': 'mlx',
    'requestAt': '2026-08-03T10:00:00.000',
    'promptSentAt': '2026-08-03T10:00:01.000',
    'firstTokenAt': '2026-08-03T10:00:01.500',
    'completedAt': '2026-08-03T10:00:03.000',
    'asr': <String, dynamic>{
      'durationMs': 200,
      'status': 'failed',
      'transcriptChars': 42,
      'mode': 'local',
      'model': 'whisper-large-v3',
      'provider': 'mlx-audio',
      'conversionMs': 15,
    },
    'toolCalls': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'search_files',
        'startAt': '2026-08-03T10:00:01.500',
        'endAt': '2026-08-03T10:00:02.000',
        'success': true,
        'arguments': <String, dynamic>{
          'alpha': 'one',
          'beta': 'two',
          'gamma':
              'a-very-long-argument-value-that-exceeds-forty-characters-easily',
          'delta': 'should-not-be-shown',
        },
      },
      <String, dynamic>{
        'name': 'read_file',
        'startAt': '2026-08-03T10:00:02.000',
        'endAt': '2026-08-03T10:00:02.250',
        'success': false,
      },
    ],
    'swiftTimings': <String, dynamic>{
      'swiftCacheHit': false,
      'swiftLoadMs': 120,
      'swiftFirstTokenMs': 80,
      'swiftGenerateMs': 900,
      'swiftTotalMs': 1100,
    },
    'error': 'stream interrupted',
    'maxTokens': 4096,
    'temperature': 0.7,
    'messages': <Map<String, dynamic>>[
      <String, dynamic>{'role': 'user', 'content': 'hello'},
    ],
    'toolSchemas': '[{"name": "search_files"}]',
    'rawChunksOutput': 'chunk-one chunk-two',
    'rawFinalResponse': 'final raw response',
    'cleanedResponse': 'cleaned final response',
  };
}

void main() {
  group('DebugSessionListView timings tab', () {
    testWidgets('renders full timings breakdown for a rich session', (
      tester,
    ) async {
      await _pumpView(tester, <Map<String, dynamic>>[_richSession()]);

      final text = _detailText(tester);

      // Header
      expect(text, contains('User: refactor the board renderer pipeline'));
      expect(text, contains('Model: qwen3-32b  [mlx]'));
      expect(text, contains('══ Timeline ═'));
      // ASR phase
      expect(text, contains('[ASR]'));
      expect(text, contains('audio → text'));
      expect(text, contains('200ms'));
      expect(text, contains('(failed)'));
      expect(text, contains('[local]'));
      expect(text, contains('42 chars'));
      expect(text, contains('↳ wav→mp3 convert'));
      expect(text, contains('15ms'));
      expect(text, contains('↳ model'));
      expect(text, contains('whisper-large-v3  [mlx-audio]'));
      // TTFT (tools variant)
      expect(text, contains('text → tools (TTFT)'));
      expect(text, contains('500ms'));
      // Tool lines
      expect(text, contains('↳ search_files'));
      expect(text, contains('✅'));
      expect(text, contains('↳ read_file'));
      expect(text, contains('250ms'));
      expect(text, contains('❌'));
      // Inline args: first three keys shown, fourth skipped, long value cut.
      expect(text, contains('alpha'));
      expect(text, contains('gamma'));
      expect(text, contains('a-very-long-argument-value-that-excee…'));
      expect(text, isNot(contains('should-not-be-shown')));
      // Final LLM phase: completedAt - lastToolEnd = 750ms
      expect(text, contains('tools → final message'));
      expect(text, contains('750ms'));
      // Totals: ASR 200 + LLM 2000 = 2200, wall = 3000
      expect(text, contains('ASR + LLM total'));
      expect(text, contains('2200ms'));
      expect(text, contains('Wall time (total)'));
      expect(text, contains('3000ms'));
      // Error section
      expect(text, contains('❌ ERROR: stream interrupted'));
      // Swift section
      expect(text, contains('══ MLX (Swift) ═'));
      expect(text, contains('MISS (loaded)'));
      expect(text, contains('load time'));
      expect(text, contains('120ms'));
      expect(text, contains('first token (TTFT)'));
      expect(text, contains('80ms'));
      expect(text, contains('generation'));
      expect(text, contains('900ms'));
      expect(text, contains('swift total'));
      expect(text, contains('1100ms'));
      // Settings section
      expect(text, contains('══ Settings ═'));
      expect(text, contains('maxTokens'));
      expect(text, contains('4096'));
      expect(text, contains('temperature'));
      expect(text, contains('0.7'));
    });

    testWidgets('renders streaming variant without tools or ASR', (
      tester,
    ) async {
      final session = <String, dynamic>{
        'userMessage': 'plain question',
        'requestAt': '2026-08-03T11:00:00.000',
        'promptSentAt': '2026-08-03T11:00:01.000',
        'firstTokenAt': '2026-08-03T11:00:02.000',
        'completedAt': '2026-08-03T11:00:05.000',
        'swiftTimings': <String, dynamic>{'swiftCacheHit': true},
      };
      await _pumpView(tester, <Map<String, dynamic>>[session]);

      final text = _detailText(tester);

      expect(text, contains('text → first token (TTFT)'));
      expect(text, contains('1000ms'));
      expect(text, contains('streaming response'));
      expect(text, contains('3000ms'));
      expect(text, isNot(contains('[ASR]')));
      expect(text, isNot(contains('[TOOL]')));
      expect(text, isNot(contains('ASR + LLM total')));
      expect(text, contains('Wall time (total)'));
      expect(text, contains('5000ms'));
      expect(text, contains('HIT ✓'));
      expect(text, isNot(contains('load time')));
      // Missing model/settings values fall back to placeholders.
      expect(text, isNot(contains('Model:')));
    });

    testWidgets('renders placeholders when timestamps are missing', (
      tester,
    ) async {
      final session = <String, dynamic>{
        'userMessage': 'no timestamps',
        'swiftTimings': <String, dynamic>{'swiftCacheHit': 'bogus'},
      };
      await _pumpView(tester, <Map<String, dynamic>>[session]);

      final text = _detailText(tester);

      expect(text, contains('text → first token (TTFT)'));
      expect(text, contains('?'));
      expect(text, isNot(contains('Wall time (total)')));
      expect(text, isNot(contains('streaming response')));
      // Unknown cache flag renders '-' for the model cache row.
      expect(text, contains('model cache'));
    });

    testWidgets('handles tool calls with missing end timestamps', (
      tester,
    ) async {
      final session = <String, dynamic>{
        'userMessage': 'incomplete tool',
        'promptSentAt': '2026-08-03T12:00:00.000',
        'firstTokenAt': '2026-08-03T12:00:01.000',
        'toolCalls': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'run_cmd', 'arguments': 'not-a-map'},
        ],
      };
      await _pumpView(tester, <Map<String, dynamic>>[session]);

      final text = _detailText(tester);

      expect(text, contains('↳ run_cmd'));
      // Duration unknown → '?' and success defaults to true (✅).
      expect(text, contains('?  ✅'));
      // Non-map arguments are ignored entirely.
      expect(text, isNot(contains('not-a-map')));
      // No last tool end → no final LLM row.
      expect(text, isNot(contains('tools → final message')));
    });
  });

  group('DebugSessionListView other tabs', () {
    testWidgets('messages tab renders captured messages as JSON', (
      tester,
    ) async {
      await _pumpView(tester, <Map<String, dynamic>>[_richSession()]);
      await _selectTab(tester, 'messages');

      final text = _detailText(tester);
      expect(text, contains('"role": "user"'));
      expect(text, contains('"content": "hello"'));
    });

    testWidgets('messages tab falls back to the prompt', (tester) async {
      final session = <String, dynamic>{'prompt': 'the raw prompt text'};
      await _pumpView(tester, <Map<String, dynamic>>[session]);
      await _selectTab(tester, 'messages');

      expect(_detailText(tester), contains('the raw prompt text'));
    });

    testWidgets('tools tab renders schemas and raw tool calls', (tester) async {
      final session = _richSession();
      session['toolCalls'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'search_files',
          'startAt': '2026-08-03T10:00:01.500',
          'endAt': '2026-08-03T10:00:02.000',
          'arguments': <String, dynamic>{'query': 'renderer'},
          'result': '{"matches": 3}',
        },
        <String, dynamic>{
          'name': 'read_file',
          'result': 'plain text result',
        },
      ];
      await _pumpView(tester, <Map<String, dynamic>>[session]);
      await _selectTab(tester, 'tools');

      final text = _detailText(tester);
      expect(text, contains('=== Tool Schemas sent to LLM ==='));
      expect(text, contains('[{"name": "search_files"}]'));
      expect(text, contains('=== Tool Calls (raw) ==='));
      expect(text, contains('Tool: search_files'));
      expect(text, contains('"query": "renderer"'));
      // JSON-decodable result is pretty-printed.
      expect(text, contains('"matches": 3'));
      // Non-JSON result falls back to the raw string.
      expect(text, contains('Tool: read_file'));
      expect(text, contains('plain text result'));
    });

    testWidgets('tools tab notes when there are no tool calls', (tester) async {
      final session = <String, dynamic>{'userMessage': 'quiet session'};
      await _pumpView(tester, <Map<String, dynamic>>[session]);
      await _selectTab(tester, 'tools');

      final text = _detailText(tester);
      expect(text, contains('(not captured yet)'));
      expect(text, contains('(no tool calls in this session)'));
    });

    testWidgets('raw output tab renders raw and cleaned responses', (
      tester,
    ) async {
      await _pumpView(tester, <Map<String, dynamic>>[_richSession()]);
      await _selectTab(tester, 'raw output');

      final text = _detailText(tester);
      expect(text, contains('=== Raw Chunks Output (before stripping) ==='));
      expect(text, contains('chunk-one chunk-two'));
      expect(text, contains('=== Raw Final Response ==='));
      expect(text, contains('final raw response'));
      expect(
        text,
        contains('=== Cleaned Response (after tool echo stripping) ==='),
      );
      expect(text, contains('cleaned final response'));
    });

    testWidgets('raw output tab omits cleaned section when absent', (
      tester,
    ) async {
      final session = <String, dynamic>{'userMessage': 'no cleaned'};
      await _pumpView(tester, <Map<String, dynamic>>[session]);
      await _selectTab(tester, 'raw output');

      final text = _detailText(tester);
      expect(text, contains('=== Raw Chunks Output (before stripping) ==='));
      expect(text, isNot(contains('=== Cleaned Response')));
    });
  });

  group('DebugSessionListView session list', () {
    testWidgets('lists sessions and switches detail on tap', (tester) async {
      final longMessage = 'b' * 40;
      final sessions = <Map<String, dynamic>>[
        <String, dynamic>{
          'userMessage': longMessage,
          'requestAt': '2026-08-03T10:05:06.000',
          'error': 'boom',
        },
        <String, dynamic>{
          'userMessage': 'second unique session body',
          'requestAt': '2026-08-03T09:01:02.000',
          'completedAt': '2026-08-03T09:01:05.000',
        },
      ];
      await _pumpView(tester, sessions);

      // First session selected by default; long message truncated to 32 + '…'.
      expect(find.text('${'b' * 32}…'), findsOneWidget);
      expect(find.text('10:05:06'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(_detailText(tester), contains('User: $longMessage'));

      // Tap the second session in the list.
      await tester.tap(find.text('second unique session body'));
      await tester.pump();
      expect(_detailText(tester), contains('User: second unique session body'));
      expect(find.text('09:01:02'), findsOneWidget);
    });

    testWidgets('shows spinner for the active (incomplete) session', (
      tester,
    ) async {
      final sessions = <Map<String, dynamic>>[
        <String, dynamic>{
          'userMessage': 'active one',
          'requestAt': '2026-08-03T10:00:00.000',
        },
      ];
      await _pumpView(tester, sessions);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state when there are no sessions', (
      tester,
    ) async {
      await _pumpView(tester, <Map<String, dynamic>>[]);

      expect(find.text('Sessions (newest first)'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });
}
