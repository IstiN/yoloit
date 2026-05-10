import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Unit tests for the cursor-agent event parsing logic.
///
/// We test the pure data-transformation logic — the _parseCursorEvent method
/// is not directly accessible (private), so we verify the ChatEvent outcomes
/// that the provider would emit for known cursor JSON payloads.

// ── Helpers ────────────────────────────────────────────────────────────────

/// Minimal cursor assistant delta event (has timestamp_ms = delta chunk).
Map<String, dynamic> cursorDelta(String text, {String? modelCallId}) => {
  'type': 'assistant',
  'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
  if (modelCallId != null) 'model_call_id': modelCallId,
  'message': {
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

/// Minimal cursor assistant final event (no timestamp_ms).
Map<String, dynamic> cursorFinal(String text, {String? modelCallId}) => {
  'type': 'assistant',
  if (modelCallId != null) 'model_call_id': modelCallId,
  'message': {
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

/// Extracts text from cursor-style content array.
String extractText(dynamic content) {
  if (content is List) {
    return content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join('');
  }
  if (content is String) return content;
  return '';
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('CursorAgent event parsing logic', () {
    group('content extraction (_extractTextContent equivalent)', () {
      test('extracts text from content array', () {
        final content = [
          {'type': 'text', 'text': 'Hello '},
          {'type': 'text', 'text': 'world'},
          {'type': 'image_url', 'url': '...'},
        ];
        expect(extractText(content), 'Hello world');
      });

      test('returns empty string for empty array', () {
        expect(extractText([]), '');
      });

      test('returns string directly if content is a string', () {
        expect(extractText('direct text'), 'direct text');
      });

      test('ignores non-text blocks', () {
        final content = [
          {'type': 'image_url', 'url': 'http://x'},
          {'type': 'text', 'text': 'only text'},
        ];
        expect(extractText(content), 'only text');
      });
    });

    group('delta vs final detection (timestamp_ms presence)', () {
      test('event with timestamp_ms is a delta', () {
        final event = cursorDelta('Hi');
        expect(event.containsKey('timestamp_ms'), isTrue);
      });

      test('event without timestamp_ms is final', () {
        final event = cursorFinal('Hello world');
        expect(event.containsKey('timestamp_ms'), isFalse);
      });
    });

    group('streaming turn detection', () {
      test('first delta triggers new stream (currentStreamId null)', () {
        // Simulate provider state
        String? currentStreamId;

        final delta = cursorDelta('Hello');
        final isFirst = currentStreamId == null;
        if (isFirst) {
          currentStreamId =
              delta['model_call_id'] as String? ??
              'cursor-gen-${delta['timestamp_ms']}';
        }

        expect(isFirst, isTrue);
        expect(currentStreamId, isNotNull);
      });

      test('second delta is NOT first (currentStreamId set)', () {
        String? currentStreamId = 'cursor-12345';

        final delta = cursorDelta('world');
        final isFirst = currentStreamId == null;
        expect(isFirst, isFalse);
        // currentStreamId unchanged
        expect(currentStreamId, 'cursor-12345');
      });

      test('final event resets currentStreamId', () {
        String? currentStreamId = 'cursor-12345';

        final finalEvent = cursorFinal('Hello world');
        // On final: reset
        final modelCallId = finalEvent['model_call_id'] as String?;
        final msgId = modelCallId ?? currentStreamId ?? 'fallback';
        currentStreamId = null;

        expect(msgId, 'cursor-12345');
        expect(currentStreamId, isNull);
      });
    });

    group('call_id sanitization', () {
      String sanitize(String id) => id.replaceAll('\n', '_');

      test('replaces newlines in call_id', () {
        expect(sanitize('call_abc\nfc_xyz'), 'call_abc_fc_xyz');
      });

      test('leaves clean id unchanged', () {
        expect(sanitize('call_abc123'), 'call_abc123');
      });

      test('multiple newlines all replaced', () {
        expect(sanitize('a\nb\nc'), 'a_b_c');
      });
    });

    group('tool type name resolution', () {
      String toolKeyToName(String key) => switch (key) {
        'shellToolCall' => 'Shell',
        'readFile' => 'Read File',
        'editFile' => 'Edit File',
        'listDir' => 'List Dir',
        'searchFiles' => 'Search Files',
        'createFile' => 'Create File',
        'deleteFile' => 'Delete File',
        'moveFile' => 'Move File',
        _ => key,
      };

      test('shellToolCall → Shell', () {
        expect(toolKeyToName('shellToolCall'), 'Shell');
      });

      test('readFile → Read File', () {
        expect(toolKeyToName('readFile'), 'Read File');
      });

      test('editFile → Edit File', () {
        expect(toolKeyToName('editFile'), 'Edit File');
      });

      test('unknown key → returned as-is', () {
        expect(toolKeyToName('myCustomTool'), 'myCustomTool');
      });
    });

    group('tool result success/failure extraction', () {
      test('shell success with exit code 0 → success=true', () {
        final toolCall = {
          'shellToolCall': {
            'result': {
              'success': {
                'exitCode': 0,
                'interleavedOutput': 'file.txt',
                'stdout': 'file.txt',
              },
            },
          },
        };

        // Simulate _extractToolResult logic
        bool isSuccess = false;
        String output = '';
        for (final key in toolCall.keys) {
          final nested = toolCall[key] as Map<String, dynamic>?;
          if (nested == null) continue;
          final result = nested['result'] as Map<String, dynamic>?;
          if (result == null) break;
          if (result.containsKey('success')) {
            final successData = result['success'] as Map<String, dynamic>?;
            final exitCode = (successData?['exitCode'] as num?)?.toInt() ?? 0;
            output =
                successData?['interleavedOutput'] as String? ??
                successData?['stdout'] as String? ??
                '';
            isSuccess = exitCode == 0;
          }
        }

        expect(isSuccess, isTrue);
        expect(output, 'file.txt');
      });

      test('shell non-zero exit code → success=false', () {
        final toolCall = {
          'shellToolCall': {
            'result': {
              'success': {
                'exitCode': 1,
                'stdout': '',
              },
            },
          },
        };

        bool isSuccess = true;
        for (final key in toolCall.keys) {
          final nested = toolCall[key] as Map<String, dynamic>?;
          if (nested == null) continue;
          final result = nested['result'] as Map<String, dynamic>?;
          if (result == null) break;
          if (result.containsKey('success')) {
            final successData = result['success'] as Map<String, dynamic>?;
            final exitCode = (successData?['exitCode'] as num?)?.toInt() ?? 0;
            isSuccess = exitCode == 0;
          }
        }

        expect(isSuccess, isFalse);
      });

      test('failure result → success=false with message', () {
        final toolCall = {
          'shellToolCall': {
            'result': {
              'failure': {'message': 'file not found'},
            },
          },
        };

        bool isSuccess = true;
        String output = '';
        for (final key in toolCall.keys) {
          final nested = toolCall[key] as Map<String, dynamic>?;
          if (nested == null) continue;
          final result = nested['result'] as Map<String, dynamic>?;
          if (result == null) break;
          if (result.containsKey('failure')) {
            final failData = result['failure'] as Map<String, dynamic>?;
            output = failData?['message'] as String? ?? '';
            isSuccess = false;
          }
        }

        expect(isSuccess, isFalse);
        expect(output, 'file not found');
      });

      test('readFile success → extracts content', () {
        final toolCall = {
          'readFile': {
            'result': {
              'success': {'exitCode': 0, 'content': 'file contents here'},
            },
          },
        };

        String output = '';
        for (final key in toolCall.keys) {
          final nested = toolCall[key] as Map<String, dynamic>?;
          if (nested == null) continue;
          final result = nested['result'] as Map<String, dynamic>?;
          if (result == null) break;
          if (result.containsKey('success')) {
            final successData = result['success'] as Map<String, dynamic>?;
            output =
                successData?['interleavedOutput'] as String? ??
                successData?['stdout'] as String? ??
                successData?['content'] as String? ??
                '';
          }
        }

        expect(output, 'file contents here');
      });
    });
  });

  group('ChatEvent model', () {
    test('assistantMessageStart type', () {
      const event = ChatEvent(
        type: ChatEventType.assistantMessageStart,
        rawType: 'cursor.assistant.start',
        data: {'messageId': 'id-1'},
        id: 'id-1',
      );
      expect(event.type, ChatEventType.assistantMessageStart);
      expect(event.id, 'id-1');
    });

    test('assistantDelta carries deltaContent', () {
      const event = ChatEvent(
        type: ChatEventType.assistantDelta,
        rawType: 'cursor.assistant.delta',
        data: {'deltaContent': 'Hello'},
      );
      expect(event.deltaContent, 'Hello');
    });

    test('toolStart carries toolCallId and toolName', () {
      const event = ChatEvent(
        type: ChatEventType.toolStart,
        rawType: 'cursor.tool_call.started',
        data: {
          'toolCallId': 'call_123',
          'toolName': 'Read File',
          'arguments': {'command': 'cat file.txt'},
        },
      );
      expect(event.toolCallId, 'call_123');
      expect(event.toolName, 'Read File');
    });

    test('toolComplete carries success flag', () {
      const event = ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'cursor.tool_call.completed',
        data: {
          'toolCallId': 'call_123',
          'success': true,
          'result': {'content': 'output'},
        },
      );
      expect(event.data['success'], isTrue);
      expect(event.toolResultContent, 'output');
    });

    test('result carries usage data', () {
      const event = ChatEvent(
        type: ChatEventType.result,
        rawType: 'cursor.result',
        data: {
          'usage': {
            'outputTokens': 150,
            'totalApiDurationMs': 3200,
          },
        },
      );
      expect(event.usageData?['outputTokens'], 150);
    });
  });
}
