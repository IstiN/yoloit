import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

// ---------------------------------------------------------------------------
// Mock engine that returns canned responses per call index.
// ---------------------------------------------------------------------------
class _MockLmEngine implements flm.LmEngine {
  _MockLmEngine({required this.responses});

  final List<String> responses;
  int _callIndex = 0;

  /// Messages sent to the engine across all calls.
  final List<List<Map<String, String>>> sentMessages = [];

  @override
  Future<String> complete(flm.LmCompletionRequest request) async {
    sentMessages.add(List<Map<String, String>>.from(
      (request.messages ?? []).map((m) => Map<String, String>.from(m)),
    ));
    if (_callIndex >= responses.length) return '';
    return responses[_callIndex++];
  }

  @override
  Future<String> completeStreaming(
    flm.LmCompletionRequest request,
    void Function(String chunk) onChunk,
  ) async {
    final text = await complete(request);
    if (text.isNotEmpty) onChunk(text);
    return text;
  }

  @override
  Map<String, Object?>? get lastNativeTimings => null;
}

// ---------------------------------------------------------------------------
// Mock tool executor that records calls but doesn't run real CLI.
// ---------------------------------------------------------------------------
class _MockToolExecutor implements YoloitToolExecutor {
  final List<({String name, Map<String, Object?> args})> calls = [];

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    calls.add((name: functionName, args: Map<String, Object?>.from(arguments)));
    return jsonEncode(<String, Object?>{
      'ok': true,
      'executed': false,
      'command': 'yoloit $functionName ${arguments.values.join(' ')}',
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
flm.InstalledModel _gemma4Model() {
  return flm.InstalledModel(
    manifest: const flm.LocalModelManifest(
      id: 'gemma4-e2b-it-4bit',
      displayName: 'Gemma 4 E2B IT 4bit',
      description: 'Test orchestrator model',
      runtimeAdapter: flm.RuntimeAdapter.mlxVlm,
      tasks: [flm.ModelTask.chat],
      source: flm.ModelSource(
        provider: 'huggingface',
        repo: 'test/gemma4',
        revision: 'main',
        license: 'apache-2.0',
      ),
      packaging: flm.PackagingSpec(
        releaseTag: 'test',
        archiveName: 'test.tar',
        chunkSizeBytes: 0,
        assetPrefix: 'test',
      ),
      requirements: flm.SystemRequirements(
        platform: 'macos-apple-silicon',
        minMemoryGb: 8,
        recommendedMemoryGb: 16,
        notes: [],
      ),
      capabilities: flm.CapabilitySpec(
        audioInput: false,
        audioOutput: false,
        toolCalling: true,
      ),
    ),
    directory: Directory.systemTemp,
    sourceLabel: 'test',
    installedAt: DateTime.now(),
    sizeBytes: 0,
  );
}

flm.InstalledModel _routerModel() {
  return flm.InstalledModel(
    manifest: const flm.LocalModelManifest(
      id: 'yoloit-router-v6',
      displayName: 'Router V6',
      description: 'Test router model',
      runtimeAdapter: flm.RuntimeAdapter.mlxLm,
      tasks: [flm.ModelTask.chat],
      source: flm.ModelSource(
        provider: 'huggingface',
        repo: 'test/router',
        revision: 'main',
        license: 'apache-2.0',
      ),
      packaging: flm.PackagingSpec(
        releaseTag: 'test',
        archiveName: 'test.tar',
        chunkSizeBytes: 0,
        assetPrefix: 'test',
      ),
      requirements: flm.SystemRequirements(
        platform: 'macos-apple-silicon',
        minMemoryGb: 4,
        recommendedMemoryGb: 8,
        notes: [],
      ),
      capabilities: flm.CapabilitySpec(
        audioInput: false,
        audioOutput: false,
        toolCalling: false,
      ),
    ),
    directory: Directory.systemTemp,
    sourceLabel: 'test',
    installedAt: DateTime.now(),
    sizeBytes: 0,
  );
}

ChatSessionConfig _config(String session) => ChatSessionConfig(
  sessionName: session,
  workingDir: '/tmp',
  provider: 'local',
  model: 'gemma4-e2b-it-4bit',
);

const _runtimeContext = ChatRuntimeContext(
  boardId: 'board-1',
  boardName: 'Test Board',
  panelId: 'panel-chat',
  panelTitle: 'YoLo Chat',
);

Future<List<ChatEvent>> _collectEvents(Stream<ChatEvent> stream) =>
    stream.toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('Orchestrator agentic loop', () {
    test('single tool call — no loop needed', () async {
      // Gemma 4 outputs a router-format JSON for a single command.
      final engine = _MockLmEngine(responses: [
        '{"c":"note:create","a":["купить молоко"]}',
        '', // Second iteration: no tool call → loop ends.
      ]);
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Создай заметку купить молоко',
        config: _config('single-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Should have exactly 1 tool call.
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts, hasLength(1));
      expect(toolStarts.first.toolName, 'note:create');

      // Executor was called once.
      expect(executor.calls, hasLength(1));
      // The compact JSON name 'note:create' is passed through normalization.
      expect(executor.calls.first.name, 'note:create');

      // Engine was called twice: iteration 1 (tool call) + iteration 2 (no more tools).
      expect(engine.sentMessages, hasLength(2));
    });

    test('multi-step tool calls — orchestrator loops', () async {
      // Iteration 1: Gemma 4 outputs first tool call.
      // Iteration 2: Gemma 4 sees result and outputs second tool call.
      // Iteration 3: Gemma 4 outputs final text (no tool call).
      final engine = _MockLmEngine(responses: [
        '{"c":"note:create","a":["позвонить артему"]}',
        '{"c":"checklist:add","a":["купить цветы"]}',
        'Готово! Создал заметку и добавил в чеклист.',
      ]);
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Создай заметку позвонить артему и добавь в чеклист купить цветы',
        config: _config('multi-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Should have 2 tool calls.
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts, hasLength(2));
      expect(toolStarts[0].toolName, 'note:create');
      expect(toolStarts[1].toolName, 'checklist:add');

      // Executor was called twice.
      expect(executor.calls, hasLength(2));

      // Engine was called 3 times (iteration 1 + 2 + 3).
      expect(engine.sentMessages, hasLength(3));

      // Iteration 2 messages should include loop context from iteration 1.
      final iter2Msgs = engine.sentMessages[1];
      // Should contain assistant + tool messages from previous iteration.
      final assistantMsgs =
          iter2Msgs.where((m) => m['role'] == 'assistant').toList();
      final toolMsgs = iter2Msgs.where((m) => m['role'] == 'tool').toList();
      expect(assistantMsgs.length, greaterThanOrEqualTo(1));
      expect(toolMsgs.length, greaterThanOrEqualTo(1));

      // Final message should contain the text response.
      final finalMsg = events
          .where((e) => e.type == ChatEventType.assistantMessage)
          .map((e) => e.messageContent)
          .join();
      expect(finalMsg, contains('Готово'));

      // Usage should report iterations.
      final result = events.where((e) => e.type == ChatEventType.result).first;
      final usage = result.usageData;
      expect(usage?['orchestratorIterations'], 3);
    });

    test('non-command message — no tool call, just text response', () async {
      final engine = _MockLmEngine(responses: [
        'Привет! Чем могу помочь?',
      ]);
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Привет!',
        config: _config('greeting-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // No tool calls.
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts, isEmpty);
      expect(executor.calls, isEmpty);

      // Engine called once.
      expect(engine.sentMessages, hasLength(1));

      // Got text response.
      final finalMsg = events
          .where((e) => e.type == ChatEventType.assistantMessage)
          .map((e) => e.messageContent)
          .join();
      expect(finalMsg, contains('Привет'));
    });

    test('max iterations safety — stops after 5', () async {
      // Engine always returns a tool call → loop should stop at 5.
      final engine = _MockLmEngine(responses: List.generate(
        10,
        (i) => '{"c":"note:create","a":["note $i"]}',
      ));
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Create many notes',
        config: _config('max-iter-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Should have at most 5 tool calls (max iterations).
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts.length, lessThanOrEqualTo(5));
      expect(engine.sentMessages.length, lessThanOrEqualTo(5));
    });

    test('router model — no loop, single iteration only', () async {
      final engine = _MockLmEngine(responses: [
        '{"c":"note:create","a":["купить молоко"]}',
        '{"c":"checklist:add","a":["extra"]}', // Should NOT be called.
      ]);
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _routerModel(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Создай заметку купить молоко',
        config: _config('router-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Router: exactly 1 tool call, no loop.
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts, hasLength(1));
      expect(engine.sentMessages, hasLength(1));
    });

    test('tool error does not stop loop', () async {
      final engine = _MockLmEngine(responses: [
        '{"c":"note:create","a":["test"]}',
        'Не удалось создать заметку, попробуйте ещё раз.',
      ]);
      // Use a special executor that returns error for first call.
      final executor = _ErrorThenOkExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Создай заметку test',
        config: _config('error-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Should have 1 tool call (error), then text response.
      final toolStarts =
          events.where((e) => e.type == ChatEventType.toolStart).toList();
      expect(toolStarts, hasLength(1));

      // Engine was called twice (tool call + final response).
      expect(engine.sentMessages, hasLength(2));

      // Final text mentions the error.
      final finalMsg = events
          .where((e) => e.type == ChatEventType.assistantMessage)
          .map((e) => e.messageContent)
          .join();
      expect(finalMsg, contains('Не удалось'));
    });

    test('loop context includes tool results', () async {
      final engine = _MockLmEngine(responses: [
        '{"c":"boards","a":[]}',
        'У вас 3 доски.',
      ]);
      final executor = _MockToolExecutor();
      final provider = LocalLlmProvider(
        engine: engine,
        installedModelLoader: () async => _gemma4Model(),
        toolExecutor: executor,
      );

      final events = await _collectEvents(provider.sendMessage(
        message: 'Сколько у меня досок?',
        config: _config('context-1'),
        isFirstMessage: true,
        runtimeContext: _runtimeContext,
      ));

      // Engine called twice.
      expect(engine.sentMessages, hasLength(2));

      // Second call should include tool result in loop context.
      final iter2Msgs = engine.sentMessages[1];
      final toolMsgs = iter2Msgs.where((m) => m['role'] == 'tool').toList();
      expect(toolMsgs.length, greaterThanOrEqualTo(1));
      expect(toolMsgs.last['content'], contains('ok'));

      // No remaining tool calls.
      expect(events.where((e) => e.type == ChatEventType.toolStart), hasLength(1));
    });
  });
}

class _ErrorThenOkExecutor implements YoloitToolExecutor {
  int _callCount = 0;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    _callCount++;
    if (_callCount == 1) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'Panel not found',
      });
    }
    return jsonEncode(<String, Object?>{
      'ok': true,
      'command': 'yoloit $functionName',
    });
  }
}
