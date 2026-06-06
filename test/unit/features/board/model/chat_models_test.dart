import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void main() {
  group('ChatMessage', () {
    test('serializes to JSON and back', () {
      final msg = ChatMessage(
        id: 'm1',
        role: ChatRole.assistant,
        content: 'hello',
        timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5),
        toolCalls: const [
          ChatToolCall(
            toolCallId: 'tc1',
            toolName: 't',
            arguments: {'a': 1},
            result: 'r',
            success: true,
          ),
        ],
        toolName: 'tn',
        toolCallId: 'tcid',
        isStreaming: true,
        tokenUsage: const ChatTokenUsage(outputTokens: 10),
        metadata: const {'k': 'v'},
        attachments: const ['file.txt'],
      );
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);
      expect(restored.id, 'm1');
      expect(restored.role, ChatRole.assistant);
      expect(restored.content, 'hello');
      expect(
        restored.timestamp?.toUtc().toIso8601String(),
        '2024-01-02T03:04:05.000Z',
      );
      expect(restored.toolCalls.length, 1);
      expect(restored.toolCalls.first.toolCallId, 'tc1');
      expect(restored.toolName, 'tn');
      expect(restored.toolCallId, 'tcid');
      // isStreaming is not persisted in toJson, so it round-trips to false.
      expect(restored.isStreaming, false);
      expect(restored.tokenUsage?.outputTokens, 10);
      expect(restored.metadata?['k'], 'v');
      expect(restored.attachments, ['file.txt']);
    });

    test('fromJson defaults missing fields', () {
      final restored = ChatMessage.fromJson(const <String, dynamic>{});
      expect(restored.id, '');
      expect(restored.role, ChatRole.system);
      expect(restored.content, '');
      expect(restored.toolCalls, isEmpty);
      expect(restored.attachments, isEmpty);
    });

    test('copyWith replaces fields', () {
      const msg = ChatMessage(id: 'm1', role: ChatRole.user, content: 'hi');
      final updated = msg.copyWith(content: 'updated', isStreaming: true);
      expect(updated.content, 'updated');
      expect(updated.isStreaming, true);
      expect(updated.id, 'm1');
    });
  });

  group('ChatToolCall', () {
    test('serializes to JSON and back', () {
      const tc = ChatToolCall(
        toolCallId: 'tc1',
        toolName: 't',
        arguments: {'a': 1},
        result: 'r',
        success: false,
      );
      final json = tc.toJson();
      final restored = ChatToolCall.fromJson(json);
      expect(restored.toolCallId, 'tc1');
      expect(restored.toolName, 't');
      expect(restored.arguments['a'], 1);
      expect(restored.result, 'r');
      expect(restored.success, false);
    });

    test('isRunning defaults to false and is not serialized', () {
      const tc = ChatToolCall(
        toolCallId: 'tc1',
        toolName: 't',
        arguments: {},
        isRunning: true,
      );
      final json = tc.toJson();
      expect(json.containsKey('isRunning'), false);
      final restored = ChatToolCall.fromJson(json);
      expect(restored.isRunning, false);
    });

    test('fromJson defaults', () {
      final restored = ChatToolCall.fromJson(const <String, dynamic>{});
      expect(restored.arguments, isEmpty);
      expect(restored.isRunning, false);
    });

    test('copyWith', () {
      const tc = ChatToolCall(
        toolCallId: 'tc1',
        toolName: 't',
        arguments: {},
      );
      final updated = tc.copyWith(result: 'done', success: true);
      expect(updated.result, 'done');
      expect(updated.success, true);
    });
  });

  group('ChatAskUser', () {
    test('copyWith updates response', () {
      const ask = ChatAskUser(question: 'Q?', choices: ['a', 'b']);
      final updated = ask.copyWith(response: 'a');
      expect(updated.question, 'Q?');
      expect(updated.response, 'a');
    });
  });

  group('ChatTokenUsage', () {
    test('serializes to JSON and back', () {
      const usage = ChatTokenUsage(
        outputTokens: 1,
        premiumRequests: 2,
        totalApiDurationMs: 3,
        sessionDurationMs: 4,
        linesAdded: 5,
        linesRemoved: 6,
      );
      final json = usage.toJson();
      final restored = ChatTokenUsage.fromJson(json);
      expect(restored.outputTokens, 1);
      expect(restored.premiumRequests, 2);
      expect(restored.totalApiDurationMs, 3);
      expect(restored.sessionDurationMs, 4);
      expect(restored.linesAdded, 5);
      expect(restored.linesRemoved, 6);
    });

    test('fromJson defaults', () {
      final restored = ChatTokenUsage.fromJson(const <String, dynamic>{});
      expect(restored.outputTokens, 0);
    });
  });

  group('ChatEvent', () {
    test('parses known event types', () {
      final cases = <String, ChatEventType>{
        'session.mcp_server_status_changed': ChatEventType.sessionStatus,
        'user.message': ChatEventType.userMessage,
        'assistant.turn_start': ChatEventType.assistantTurnStart,
        'assistant.message_start': ChatEventType.assistantMessageStart,
        'assistant.message_delta': ChatEventType.assistantDelta,
        'assistant.message': ChatEventType.assistantMessage,
        'assistant.turn_end': ChatEventType.assistantTurnEnd,
        'tool.execution_start': ChatEventType.toolStart,
        'tool.execution_complete': ChatEventType.toolComplete,
        'ask_user.question': ChatEventType.askUser,
        'result': ChatEventType.result,
        'unknown': ChatEventType.unknown,
      };
      for (final entry in cases.entries) {
        final event = ChatEvent.fromJson(<String, dynamic>{'type': entry.key});
        expect(event.type, entry.value, reason: entry.key);
      }
    });

    test('result event preserves top-level data', () {
      final event = ChatEvent.fromJson(<String, dynamic>{
        'type': 'result',
        'usage': {'outputTokens': 42},
        'sessionId': 's1',
      });
      expect(event.type, ChatEventType.result);
      expect(event.data['usage'], isA<Map<String, dynamic>>());
      expect(event.data['sessionId'], 's1');
    });

    test('parses timestamp', () {
      final event = ChatEvent.fromJson(<String, dynamic>{
        'type': 'user.message',
        'timestamp': '2024-01-02T03:04:05.000Z',
      });
      expect(event.timestamp, DateTime.utc(2024, 1, 2, 3, 4, 5));
    });

    test('accessors', () {
      const event = ChatEvent(
        type: ChatEventType.assistantDelta,
        rawType: 'assistant.message_delta',
        data: {'deltaContent': 'hi'},
      );
      expect(event.deltaContent, 'hi');
    });

    test('messageContent and messageId', () {
      const event = ChatEvent(
        type: ChatEventType.assistantMessage,
        rawType: 'assistant.message',
        data: {'content': 'hello', 'messageId': 'm1'},
      );
      expect(event.messageContent, 'hello');
      expect(event.messageId, 'm1');
    });

    test('tool accessors', () {
      const event = ChatEvent(
        type: ChatEventType.toolStart,
        rawType: 'tool.execution_start',
        data: {
          'toolName': 'read',
          'toolCallId': 'tc1',
          'arguments': {'path': '/tmp'},
        },
      );
      expect(event.toolName, 'read');
      expect(event.toolCallId, 'tc1');
      expect(event.toolArguments?['path'], '/tmp');
    });

    test('toolResultContent and toolSuccess', () {
      const event = ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'tool.execution_complete',
        data: {
          'success': true,
          'result': {'content': 'done'},
        },
      );
      expect(event.toolResultContent, 'done');
      expect(event.toolSuccess, true);
    });

    test('subagent accessors', () {
      const event = ChatEvent(
        type: ChatEventType.subagentStarted,
        rawType: 'subagent.started',
        data: {
          'agentId': 'a1',
          'parentToolCallId': 'ptc1',
          'agentDisplayName': '  Agent X  ',
          'agentDescription': '  desc  ',
          'outputTokens': 7,
          'usage': {'total': 1},
          'toolRequests': [<String, dynamic>{}],
        },
      );
      expect(event.agentId, 'a1');
      expect(event.parentToolCallId, 'ptc1');
      expect(event.agentName, 'Agent X');
      expect(event.agentDescription, 'desc');
      expect(event.outputTokens, 7);
      expect(event.usageData, isA<Map<String, dynamic>>());
      expect(event.toolRequests, [{}]);
    });
  });

  group('ChatSessionConfig', () {
    test('serializes to JSON and back', () {
      const config = ChatSessionConfig(
        sessionName: 's1',
        workingDir: '/tmp',
        provider: 'cursor',
        model: 'claude',
        reasoningEffort: 'high',
        autopilot: true,
        mode: 'plan',
        maxAutopilotContinues: 5,
        customArgs: ['--foo'],
        envGroupIds: ['g1'],
        disabledLocalToolNames: ['t1'],
      );
      final json = config.toJson();
      final restored = ChatSessionConfig.fromJson(json);
      expect(restored.sessionName, 's1');
      expect(restored.workingDir, '/tmp');
      expect(restored.provider, 'cursor');
      expect(restored.model, 'claude');
      expect(restored.reasoningEffort, 'high');
      expect(restored.autopilot, true);
      expect(restored.mode, 'plan');
      expect(restored.maxAutopilotContinues, 5);
      expect(restored.customArgs, ['--foo']);
      expect(restored.envGroupIds, ['g1']);
      expect(restored.disabledLocalToolNames, ['t1']);
    });

    test('fromJson defaults', () {
      final restored = ChatSessionConfig.fromJson(const <String, dynamic>{});
      expect(restored.provider, 'copilot');
      expect(restored.model, 'gpt-5-mini');
      expect(restored.autopilot, false);
      expect(restored.maxAutopilotContinues, 99);
    });

    test('copyWith clears nullable fields via function', () {
      const config = ChatSessionConfig(
        sessionName: 's1',
        workingDir: '/tmp',
        reasoningEffort: 'high',
        mode: 'plan',
      );
      final updated = config.copyWith(
        reasoningEffort: () => null,
        mode: () => null,
      );
      expect(updated.reasoningEffort, isNull);
      expect(updated.mode, isNull);
    });
  });

  group('ChatModelInfo', () {
    test('serializes to JSON and back', () {
      const model = ChatModelInfo(
        id: 'm1',
        displayName: 'Model 1',
        costMultiplier: 1.5,
        isDefault: true,
        inputCostPerMillion: 2,
        outputCostPerMillion: 3,
        contextWindow: 4000,
        providerGroup: 'g1',
      );
      final json = model.toJson();
      final restored = ChatModelInfo.fromJson(json);
      expect(restored.id, 'm1');
      expect(restored.displayName, 'Model 1');
      expect(restored.costMultiplier, 1.5);
      expect(restored.isDefault, true);
      expect(restored.inputCostPerMillion, 2);
      expect(restored.outputCostPerMillion, 3);
      expect(restored.contextWindow, 4000);
      expect(restored.providerGroup, 'g1');
    });

    test('isFree detects free models', () {
      const free1 = ChatModelInfo(id: 'a', displayName: 'A');
      const free2 = ChatModelInfo(
        id: 'b',
        displayName: 'B',
        inputCostPerMillion: 0,
        outputCostPerMillion: 0,
      );
      const paid = ChatModelInfo(
        id: 'c',
        displayName: 'C',
        inputCostPerMillion: 1,
      );
      expect(free1.isFree, true);
      expect(free2.isFree, true);
      expect(paid.isFree, false);
    });

    test('model lists contain entries', () {
      expect(kCopilotModels, isNotEmpty);
      expect(kCursorModels, isNotEmpty);
      expect(kKimiModels, isNotEmpty);
      expect(kCodexModels, isNotEmpty);
      expect(kLocalModels, isNotEmpty);
      expect(kOpencodeModels, isNotEmpty);
    });
  });
}
