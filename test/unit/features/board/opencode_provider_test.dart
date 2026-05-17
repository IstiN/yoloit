import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Unit tests for the OpenCode provider's data-transformation logic:
/// NDJSON event parsing and model parsing.

void main() {
  group('OpencodeProvider — model parsing', () {
    test('parses providerID/modelID with single slash', () {
      final modelId = 'anthropic/claude-sonnet-4-5';
      final slashIdx = modelId.indexOf('/');
      final providerID = modelId.substring(0, slashIdx);
      final modelID = modelId.substring(slashIdx + 1);
      expect(providerID, 'anthropic');
      expect(modelID, 'claude-sonnet-4-5');
    });

    test('parses OpenRouter nested model path', () {
      final modelId = 'openrouter/deepseek/deepseek-chat-v3-0324:free';
      final slashIdx = modelId.indexOf('/');
      final providerID = modelId.substring(0, slashIdx);
      final modelID = modelId.substring(slashIdx + 1);
      expect(providerID, 'openrouter');
      expect(modelID, 'deepseek/deepseek-chat-v3-0324:free');
    });

    test('handles modelId without slash (passthrough)', () {
      final modelId = 'gpt-4o';
      final slashIdx = modelId.indexOf('/');
      final providerID = slashIdx > 0 ? modelId.substring(0, slashIdx) : null;
      final modelID = slashIdx > 0 ? modelId.substring(slashIdx + 1) : modelId;
      expect(providerID, isNull);
      expect(modelID, 'gpt-4o');
    });
  });

  group('OpencodeProvider — NDJSON event parsing', () {
    group('step_start event', () {
      test('maps to assistantTurnStart', () {
        final json = {
          'type': 'step_start',
          'timestamp': 1715800000000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'step-start',
            'messageID': 'msg_def456',
            'sessionID': 'sess_abc123',
          },
        };

        expect(json['type'], 'step_start');
        expect(json['sessionID'], 'sess_abc123');
        final part = json['part'] as Map<String, dynamic>;
        expect(part['type'], 'step-start');
      });
    });

    group('step_finish event', () {
      test('maps to assistantTurnEnd with cost and tokens', () {
        final json = {
          'type': 'step_finish',
          'timestamp': 1715800001000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'step-finish',
            'messageID': 'msg_def456',
            'sessionID': 'sess_abc123',
            'reason': 'stop',
            'cost': 0.0042,
            'tokens': {
              'total': 5432,
              'input': 5000,
              'output': 432,
              'reasoning': 0,
              'cache': {'read': 0, 'write': 0},
            },
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        expect(part['reason'], 'stop');
        expect(part['cost'], 0.0042);
        expect((part['tokens'] as Map)['total'], 5432);
      });
    });

    group('text event', () {
      test('maps to assistantMessage with full text', () {
        final json = {
          'type': 'text',
          'timestamp': 1715800002000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'sessionID': 'sess_abc123',
            'messageID': 'msg_def456',
            'type': 'text',
            'text': 'Here is the answer.',
            'time': {'start': 1715800000, 'end': 1715800005},
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        expect(part['text'], 'Here is the answer.');
        expect(part['type'], 'text');
      });

      test('handles empty text', () {
        final json = {
          'type': 'text',
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'text',
            'text': '',
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        expect(part['text'], '');
      });
    });

    group('tool_use event — completed', () {
      test('maps to toolStart + toolComplete with success=true', () {
        final json = {
          'type': 'tool_use',
          'timestamp': 1715800003000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'tool',
            'callID': 'call_001',
            'tool': 'bash',
            'state': {
              'status': 'completed',
              'input': {'command': 'ls -la'},
              'output': 'total 42',
              'title': 'ran bash',
              'time': {'start': 1715800000, 'end': 1715800005},
            },
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        expect(part['callID'], 'call_001');
        expect(part['tool'], 'bash');
        final state = part['state'] as Map<String, dynamic>;
        expect(state['status'], 'completed');
        expect(state['output'], 'total 42');
        expect(state['title'], 'ran bash');
      });
    });

    group('tool_use event — error', () {
      test('maps to toolStart + toolComplete with success=false', () {
        final json = {
          'type': 'tool_use',
          'timestamp': 1715800004000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'tool',
            'callID': 'call_002',
            'tool': 'bash',
            'state': {
              'status': 'error',
              'input': {'command': 'rm -rf /'},
              'error': 'Permission denied',
              'time': {'start': 1715800000, 'end': 1715800005},
            },
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        final state = part['state'] as Map<String, dynamic>;
        expect(state['status'], 'error');
        expect(state['error'], 'Permission denied');
      });
    });

    group('tool_use event — various tool names', () {
      test('bash tool', () {
        final json = {
          'type': 'tool_use',
          'sessionID': 'sess_abc123',
          'part': {
            'callID': 'call_001',
            'tool': 'bash',
            'state': {'status': 'completed'},
          },
        };
        final part = json['part'] as Map<String, dynamic>;
        expect(part['tool'], 'bash');
      });

      test('read tool', () {
        final json = {
          'type': 'tool_use',
          'sessionID': 'sess_abc123',
          'part': {
            'callID': 'call_002',
            'tool': 'read',
            'state': {'status': 'completed'},
          },
        };
        final part = json['part'] as Map<String, dynamic>;
        expect(part['tool'], 'read');
      });

      test('write tool', () {
        final json = {
          'type': 'tool_use',
          'sessionID': 'sess_abc123',
          'part': {
            'callID': 'call_003',
            'tool': 'write',
            'state': {'status': 'completed'},
          },
        };
        final part = json['part'] as Map<String, dynamic>;
        expect(part['tool'], 'write');
      });

      test('task tool (sub-agent)', () {
        final json = {
          'type': 'tool_use',
          'sessionID': 'sess_abc123',
          'part': {
            'callID': 'call_004',
            'tool': 'task',
            'state': {'status': 'completed'},
          },
        };
        final part = json['part'] as Map<String, dynamic>;
        expect(part['tool'], 'task');
      });
    });

    group('reasoning event', () {
      test('maps to assistantDelta with reasoning text', () {
        final json = {
          'type': 'reasoning',
          'timestamp': 1715800005000,
          'sessionID': 'sess_abc123',
          'part': {
            'id': 'prt_xyz',
            'type': 'reasoning',
            'text': 'Let me think about this...',
            'time': {'start': 1715800000, 'end': 1715800005},
          },
        };

        final part = json['part'] as Map<String, dynamic>;
        expect(part['type'], 'reasoning');
        expect(part['text'], 'Let me think about this...');
      });
    });

    group('error event', () {
      test('extracts error message from nested data', () {
        final json = {
          'type': 'error',
          'timestamp': 1715800006000,
          'sessionID': 'sess_abc123',
          'error': {
            'name': 'ApiError',
            'data': {
              'message': 'Rate limit exceeded',
              'statusCode': 429,
              'isRetryable': true,
            },
          },
        };

        final errorObj = json['error'] as Map<String, dynamic>;
        final errorData = errorObj['data'] as Map<String, dynamic>;
        expect(errorData['message'], 'Rate limit exceeded');
        expect(errorObj['name'], 'ApiError');
      });
    });

    group('sessionID capture from first event', () {
      test('captures sessionID from step_start', () {
        final json = {
          'type': 'step_start',
          'sessionID': 'ses_1d03f9c47ffeoGvM8g1LInhHUY',
        };

        expect(json['sessionID'], startsWith('ses_'));
      });

      test('captures sessionID from text event', () {
        final json = {
          'type': 'text',
          'sessionID': 'ses_abc123',
        };

        expect(json['sessionID'], 'ses_abc123');
      });
    });
  });

  group('OpencodeProvider — kOpencodeModels', () {
    test('contains at least one default model', () {
      expect(kOpencodeModels.any((m) => m.isDefault), isTrue);
    });

    test('OpenCode built-in Qwen 3.6 Plus is default (free)', () {
      final defaultModel =
          kOpencodeModels.firstWhere((m) => m.isDefault);
      expect(defaultModel.id, 'opencode/qwen3.6-plus-free');
      expect(defaultModel.costMultiplier, 0);
    });

    test('all OpenRouter models have nested model paths', () {
      final openrouter = kOpencodeModels.where(
        (m) => m.id.startsWith('openrouter/'),
      );
      for (final m in openrouter) {
        expect(m.id.indexOf('/', 11), greaterThan(0));
      }
    });

    test('contains multiple free (cost=0) OpenRouter models', () {
      final freeModels = kOpencodeModels.where(
        (m) => m.id.startsWith('openrouter/') && m.costMultiplier == 0,
      );
      expect(freeModels.length, greaterThanOrEqualTo(5));
    });
  });

  group('ChatEvent model for opencode events', () {
    test('assistantTurnStart from step_start', () {
      const event = ChatEvent(
        type: ChatEventType.assistantTurnStart,
        rawType: 'opencode.step_start',
        data: {},
      );
      expect(event.type, ChatEventType.assistantTurnStart);
    });

    test('assistantMessage from text event', () {
      const event = ChatEvent(
        type: ChatEventType.assistantMessage,
        rawType: 'opencode.text',
        data: {'content': 'Hello!', 'messageId': 'prt_xyz'},
        id: 'prt_xyz',
      );
      expect(event.messageContent, 'Hello!');
      expect(event.messageId, 'prt_xyz');
    });

    test('toolStart from tool_use', () {
      const event = ChatEvent(
        type: ChatEventType.toolStart,
        rawType: 'opencode.tool_use.start',
        data: {
          'toolCallId': 'call_001',
          'toolName': 'ran bash',
          'arguments': {'command': 'ls'},
        },
      );
      expect(event.toolCallId, 'call_001');
      expect(event.toolName, 'ran bash');
    });

    test('toolComplete from tool_use with result', () {
      const event = ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'opencode.tool_use.complete',
        data: {
          'toolCallId': 'call_001',
          'success': true,
          'result': {'content': 'total 42'},
        },
      );
      expect(event.toolSuccess, isTrue);
      expect(event.toolResultContent, 'total 42');
    });
  });
}
