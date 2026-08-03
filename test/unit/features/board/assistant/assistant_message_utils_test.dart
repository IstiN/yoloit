import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/assistant/assistant_message_utils.dart';

void main() {
  group('normalizeOverlayToolLogEntry', () {
    test('strips running prefix and marks as in-progress', () {
      expect(
        normalizeOverlayToolLogEntry('⏳ running: panel:create'),
        '⚙️ panel:create',
      );
    });

    test('marks succeeded entries with check icon', () {
      expect(normalizeOverlayToolLogEntry('✅ panel:create'), '✅ panel:create');
    });

    test('marks failed entries with cross icon', () {
      expect(normalizeOverlayToolLogEntry('❌ panel:create'), '❌ panel:create');
    });

    test('plain entries get the gear icon', () {
      expect(normalizeOverlayToolLogEntry('web:search'), '⚙️ web:search');
    });
  });

  group('composeAssistantOverlayResponse', () {
    test('returns trimmed text when there are no tool logs', () {
      expect(composeAssistantOverlayResponse('  hello  ', const []), 'hello');
    });

    test('returns only tool lines when assistant text is empty', () {
      expect(
        composeAssistantOverlayResponse('  ', ['✅ panels', '⏳ running: note']),
        '✅ panels\n⚙️ note',
      );
    });

    test('combines tool lines and assistant text', () {
      expect(
        composeAssistantOverlayResponse('done', ['✅ panels']),
        '✅ panels\n\ndone',
      );
    });

    test('keeps only the last 5 tool log entries', () {
      final logs = List<String>.generate(7, (i) => 'tool-$i');
      final result = composeAssistantOverlayResponse('', logs);
      expect(result, contains('tool-2'));
      expect(result, contains('tool-6'));
      expect(result, isNot(contains('tool-1')));
    });
  });

  group('assistantOverlayStatus', () {
    test('is processing while generating with no content and no tools', () {
      expect(
        assistantOverlayStatus(
          isGenerating: true,
          content: '  ',
          overlayToolLogs: const [],
        ),
        'processing',
      );
    });

    test('is responding while generating with content', () {
      expect(
        assistantOverlayStatus(
          isGenerating: true,
          content: 'hi',
          overlayToolLogs: const [],
        ),
        'responding',
      );
    });

    test('is responding while generating with tool logs', () {
      expect(
        assistantOverlayStatus(
          isGenerating: true,
          content: '',
          overlayToolLogs: const ['✅ panels'],
        ),
        'responding',
      );
    });

    test('is output when not generating', () {
      expect(
        assistantOverlayStatus(
          isGenerating: false,
          content: '',
          overlayToolLogs: const [],
        ),
        'output',
      );
    });
  });

  group('replaceMessageContentInPlace', () {
    test('replaces content of the matching message only', () {
      final messages = <Map<String, dynamic>>[
        {'id': 'a', 'role': 'user', 'content': 'old'},
        {'id': 'b', 'role': 'assistant', 'content': 'keep'},
      ];
      final found = replaceMessageContentInPlace(messages, 'a', 'new');
      expect(found, isTrue);
      expect(messages[0]['content'], 'new');
      expect(messages[0]['role'], 'user');
      expect(messages[1]['content'], 'keep');
    });

    test('returns false when no message matches', () {
      final messages = <Map<String, dynamic>>[
        {'id': 'a', 'content': 'old'},
      ];
      expect(replaceMessageContentInPlace(messages, 'zzz', 'new'), isFalse);
      expect(messages[0]['content'], 'old');
    });
  });

  group('cleanAssistantToolEchoes', () {
    test('keeps plain assistant text', () {
      expect(cleanAssistantToolEchoes('  Hello there  ', const []), 'Hello there');
    });

    test('drops a leading tool echo block with ok payload', () {
      final cleaned = cleanAssistantToolEchoes(
        '[yoloit_panels] {"ok": true, "stdout": "..."}',
        const ['panels'],
      );
      expect(cleaned, 'Готово — выполнил через panels.');
    });

    test('drops standalone tool echo lines but keeps real text', () {
      final cleaned = cleanAssistantToolEchoes(
        'Here is your note.\n[yoloit_panels] ok',
        const [],
      );
      expect(cleaned, 'Here is your note.');
    });

    test('clears content starting with a tool echo containing a command', () {
      final cleaned = cleanAssistantToolEchoes(
        '[yoloit_note] {"command": "note"}\nHere is your note.',
        const ['note'],
      );
      expect(cleaned, 'Готово — выполнил через note.');
    });

    test('returns empty string when nothing remains and no tools called', () {
      expect(cleanAssistantToolEchoes('[yoloit_panels] ok', const []), '');
    });

    test('fallback deduplicates called tools', () {
      final cleaned = cleanAssistantToolEchoes('', ['panels', 'note', 'panels']);
      expect(cleaned, 'Готово — выполнил через panels, note.');
    });
  });

  group('compactAssistantToolResult', () {
    test('returns the command on success when present', () {
      final result = compactAssistantToolResult(
        'panels',
        jsonEncode({'ok': true, 'command': 'yoloit panels board1'}),
        true,
      );
      expect(result, 'yoloit panels board1');
    });

    test('returns Done with tool name on success without command', () {
      expect(compactAssistantToolResult('panels', '{"ok": true}', true), 'Done: panels');
      expect(compactAssistantToolResult('panels', 'not json', true), 'Done: panels');
    });

    test('returns extracted error on failure', () {
      final result = compactAssistantToolResult(
        'note',
        jsonEncode({'ok': false, 'error': 'panel not found'}),
        false,
      );
      expect(result, 'Tool failed: panel not found');
    });

    test('falls back to tool name on failure without error', () {
      expect(compactAssistantToolResult('note', '{"ok": false}', false), 'Tool failed: note');
      expect(compactAssistantToolResult('note', 'garbage', false), 'Tool failed: note');
    });
  });

  group('toolResultReportedFailure', () {
    test('detects ok: false', () {
      expect(toolResultReportedFailure('{"ok": false}'), isTrue);
    });

    test('ok: true and invalid json are not failures', () {
      expect(toolResultReportedFailure('{"ok": true}'), isFalse);
      expect(toolResultReportedFailure('nope'), isFalse);
      expect(toolResultReportedFailure('[1,2]'), isFalse);
    });
  });

  group('panelCreateTargetPatch', () {
    test('returns empty patch for non-note panel types', () {
      expect(
        panelCreateTargetPatch(
          arguments: const {'type': 'board.webpage'},
          result: '{}',
        ),
        isEmpty,
      );
    });

    test('extracts panel id and title from stdout payload', () {
      final result = jsonEncode({
        'ok': true,
        'stdout': jsonEncode({
          'panel': {'id': 'p1', 'title': 'Shopping list'},
        }),
      });
      expect(
        panelCreateTargetPatch(
          arguments: const {'type': 'board.note.markdown'},
          result: result,
        ),
        {'lastTargetNotePanelId': 'p1', 'lastTargetNotePanelTitle': 'Shopping list'},
      );
    });

    test('accepts payload directly at the top level', () {
      final result = jsonEncode({
        'panel': {'id': 'p2', 'title': 'Todo'},
      });
      expect(
        panelCreateTargetPatch(
          arguments: const {'type': 'board.note.markdown'},
          result: result,
        ),
        {'lastTargetNotePanelId': 'p2', 'lastTargetNotePanelTitle': 'Todo'},
      );
    });

    test('falls back to id when title is missing or blank', () {
      final result = jsonEncode({
        'panel': {'id': 'p3', 'title': '  '},
      });
      expect(
        panelCreateTargetPatch(
          arguments: const {'type': 'board.note.markdown'},
          result: result,
        ),
        {'lastTargetNotePanelId': 'p3', 'lastTargetNotePanelTitle': 'p3'},
      );
    });

    test('returns empty patch for malformed payloads', () {
      const args = {'type': 'board.note.markdown'};
      expect(panelCreateTargetPatch(arguments: args, result: 'not json'), isEmpty);
      expect(panelCreateTargetPatch(arguments: args, result: '[1]'), isEmpty);
      expect(
        panelCreateTargetPatch(arguments: args, result: '{"panel": "x"}'),
        isEmpty,
      );
      expect(
        panelCreateTargetPatch(arguments: args, result: '{"panel": {"id": " "}}'),
        isEmpty,
      );
    });
  });

  group('toolTargetPatchIfNeeded', () {
    const selfId = 'assistant-1';

    test('ignores failed tool results', () {
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'note:write',
          arguments: const {'panel': 'p1'},
          result: '{"ok": false}',
          selfPanelId: selfId,
        ),
        isEmpty,
      );
    });

    test('delegates panel:create to panelCreateTargetPatch', () {
      final result = jsonEncode({
        'panel': {'id': 'p9', 'title': 'Note'},
      });
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'panel:create',
          arguments: const {'type': 'board.note.markdown'},
          result: result,
          selfPanelId: selfId,
        ),
        {'lastTargetNotePanelId': 'p9', 'lastTargetNotePanelTitle': 'Note'},
      );
    });

    test('retargets for note commands with another panel', () {
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'note:append',
          arguments: const {'panel': 'note-7'},
          result: '{"ok": true}',
          selfPanelId: selfId,
        ),
        {'lastTargetNotePanelId': 'note-7', 'lastTargetNotePanelTitle': 'note-7'},
      );
    });

    test('ignores note command targeting the assistant panel itself', () {
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'note',
          arguments: const {'panel': selfId},
          result: '{"ok": true}',
          selfPanelId: selfId,
        ),
        isEmpty,
      );
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'note',
          arguments: const {'panel': '  '},
          result: '{"ok": true}',
          selfPanelId: selfId,
        ),
        isEmpty,
      );
    });

    test('returns empty patch for unrelated commands', () {
      expect(
        toolTargetPatchIfNeeded(
          toolCommand: 'panels',
          arguments: const {},
          result: '{"ok": true}',
          selfPanelId: selfId,
        ),
        isEmpty,
      );
    });
  });

  group('conversationMessagesForRequest', () {
    test('keeps non-empty user and assistant messages in order', () {
      final result = conversationMessagesForRequest([
        {'role': 'user', 'content': '  hi  '},
        {'role': 'assistant', 'content': 'hello'},
        {'role': 'user', 'content': '   '},
        {'role': 'system', 'content': 'ignored'},
        {'role': 'assistant', 'content': ''},
      ]);
      expect(result, [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
    });

    test('formats tool messages through the prompt formatter', () {
      final result = conversationMessagesForRequest([
        {
          'role': 'tool',
          'toolName': 'panels',
          'success': true,
          'arguments': {'board': 'b1'},
          'rawResult': '{"ok": true}',
        },
      ]);
      expect(result, hasLength(1));
      expect(result.single['role'], 'tool');
      expect(result.single['content'], contains('Tool panels succeeded'));
      expect(result.single['content'], contains('Tool arguments:'));
      expect(result.single['content'], contains('Tool result:'));
    });
  });

  group('formatToolMessageForPrompt', () {
    test('marks failed tools and defaults missing fields', () {
      final text = formatToolMessageForPrompt({
        'role': 'tool',
        'success': false,
        'rawResult': '{"ok": false, "error": "boom"}',
      });
      expect(text, contains('Tool tool failed'));
      expect(text, contains('boom'));
    });
  });

  group('formatChatMessageLogEntry', () {
    test('renders role, content and tool calls', () {
      final entry = formatChatMessageLogEntry({
        'role': 'assistant',
        'content': 'Working on it',
        'toolCalls': [
          {
            'toolName': 'panels',
            'arguments': {'board': 'b1'},
            'result': 'ok',
          },
          'not-a-map',
        ],
      });
      expect(entry, contains('--- [assistant] ---'));
      expect(entry, contains('Working on it'));
      expect(entry, contains('[tool] panels({board: b1})'));
      expect(entry, contains('[result] ok'));
      expect(entry, isNot(contains('not-a-map')));
    });

    test('handles missing role and tool call without result', () {
      final entry = formatChatMessageLogEntry({
        'content': 'hi',
        'toolCalls': [
          {'toolName': 'note', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(entry, contains('--- [unknown] ---'));
      expect(entry, contains('[tool] note({})'));
      expect(entry, isNot(contains('[result]')));
    });
  });

  group('formatDebugSessionLogEntry', () {
    test('renders user message, error and response', () {
      final entry = formatDebugSessionLogEntry({
        'userMessage': 'do things',
        'error': 'timeout',
        'response': 'partial answer',
      });
      expect(entry, contains('User: do things'));
      expect(entry, contains('ERROR: timeout'));
      expect(entry, contains('Response: partial answer'));
    });

    test('truncates long responses to 500 chars', () {
      final long = 'x' * 600;
      final entry = formatDebugSessionLogEntry({'response': long});
      expect(entry, contains('Response: ${'x' * 500}'));
      expect(entry, isNot(contains('x' * 501)));
    });

    test('omits empty response and missing error', () {
      final entry = formatDebugSessionLogEntry({'userMessage': 'q'});
      expect(entry, contains('User: q'));
      expect(entry, isNot(contains('ERROR')));
      expect(entry, isNot(contains('Response')));
    });
  });

  group('buildFullChatLogsText', () {
    test('renders header and messages without debug section', () {
      final text = buildFullChatLogsText(
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        debugSessions: const [],
      );
      expect(text, contains('=== YoLoIT Chat Logs ==='));
      expect(text, contains('Messages: 1'));
      expect(text, contains('--- [user] ---'));
      expect(text, isNot(contains('=== LLM Debug Sessions ===')));
    });

    test('appends debug sessions when present', () {
      final text = buildFullChatLogsText(
        messages: const [],
        debugSessions: [
          {'userMessage': 'sim', 'response': 'answer'},
        ],
      );
      expect(text, contains('Messages: 0'));
      expect(text, contains('=== LLM Debug Sessions ==='));
      expect(text, contains('User: sim'));
      expect(text, contains('Response: answer'));
    });
  });

  group('microphone permission hint text', () {
    test('reset command targets the bundle id', () {
      expect(
        microphonePermissionResetCommand('com.example.app'),
        'tccutil reset Microphone com.example.app',
      );
    });

    test('hint text contains app, bundle, status and reset command', () {
      final text = buildMicrophonePermissionHintText(
        appName: 'YoLoIT Debug',
        bundleId: 'com.example.app',
        status: 'denied',
      );
      expect(text, contains('YoLoIT Debug'));
      expect(text, contains('Bundle id: com.example.app'));
      expect(text, contains('macOS status: denied'));
      expect(text, contains('tccutil reset Microphone com.example.app'));
    });
  });
}
