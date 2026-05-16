import 'dart:convert';
import 'dart:io';

import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:yoloit/core/platform/local_model_registry_locator.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class RealLlmToolTestRunner {
  RealLlmToolTestRunner._();

  static const flag = '--yoloit-real-llm-tool-test';

  static bool isRequested(List<String> args) => args.contains(flag);

  static Future<int> run(List<String> args) async {
    try {
      final fixture = _loadFixture(
        _argValue(args, flag) ??
            'test/fixtures/local_chat_real_llm_tool_cases.json',
      );
      final installed = await _loadInstalledModel(
        _argValue(args, '--model-id') ??
            Platform.environment['YOLOIT_REAL_LLM_MODEL_ID'],
      );
      final categories = _argValues(
        _argValue(args, '--case-category') ??
            Platform.environment['YOLOIT_REAL_LLM_TOOL_CASE_CATEGORY'],
      );
      final caseLimit = int.tryParse(_argValue(args, '--case-limit') ?? '');
      final filteredCases =
          categories.isEmpty
              ? fixture.cases
              : fixture.cases
                  .where((item) => categories.contains(item.category))
                  .toList(growable: false);
      final cases =
          caseLimit == null
              ? filteredCases
              : filteredCases.take(caseLimit).toList(growable: false);
      final results = <Map<String, Object?>>[];

      stderr.writeln(
        '\n📊 Running ${cases.length} tool test cases on ${installed.manifest.id}...\n',
      );

      for (int i = 0; i < cases.length; i++) {
        final item = cases[i];
        final stopwatch = Stopwatch()..start();
        final result = await _runCase(installed, fixture.runtimeContext, item);
        stopwatch.stop();
        results.add(result);

        final status = result['ok'] == true ? '✓' : '✗';
        final duration = stopwatch.elapsedMilliseconds;
        final tool = result['actualTool'] ?? 'N/A';
        final expected = result['expectedTool'] ?? 'N/A';
        stderr.writeln(
          '$status [${i + 1}/${cases.length}] ${item.id} → $tool (expected: $expected) [${duration}ms]',
        );

        if (result['ok'] != true) {
          final error = result['error'];
          if (error != null) {
            stderr.writeln('   ❌ Error: $error');
          }
          final mismatches = result['argumentMismatches'];
          if (mismatches != null) {
            for (final mismatch in mismatches as List) {
              final mismatchMap = mismatch as Map<String, Object?>;
              stderr.writeln(
                '   ⚠️  Arg "${mismatchMap['key']}" expected: ${mismatchMap['expected']}, got: ${mismatchMap['actual']}',
              );
            }
          }
        }
      }

      stderr.writeln('');

      final ok = results.every((result) => result['ok'] == true);
      final passed = results.where((r) => r['ok'] == true).length;
      final failed = results.length - passed;

      stderr.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      final statusText =
          failed > 0 ? '($failed failed)' : '(100% ✓)';
      stderr.writeln(
        '📈 Results: $passed/${results.length} passed $statusText',
      );
      stderr.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'ok': ok,
          'modelId': installed.manifest.id,
          'caseCount': cases.length,
          'passed': passed,
          'failed': failed,
          if (categories.isNotEmpty) 'categories': categories.toList(),
          'results': results,
        }),
      );
      return ok ? 0 : 1;
    } catch (error, stackTrace) {
      stderr.writeln(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'ok': false,
          'error': '$error',
          'stackTrace': '$stackTrace',
        }),
      );
      return 1;
    }
  }

  static Future<Map<String, Object?>> _runCase(
    flm.InstalledModel installed,
    ChatRuntimeContext runtimeContext,
    _RealToolCase item,
  ) async {
    final provider = LocalLlmProvider(
      installedModelLoader: () async => installed,
      toolExecutor: YoloitCliToolExecutor(execute: false),
    );
    final events =
        await provider
            .sendMessage(
              message: item.message,
              config: ChatSessionConfig(
                sessionName: 'real-llm-${item.id}',
                workingDir: Directory.current.path,
                provider: 'local',
                model: installed.manifest.id,
              ),
              isFirstMessage: true,
              runtimeContext: runtimeContext,
            )
            .timeout(const Duration(minutes: 3))
            .toList();

    final toolStarts =
        events.where((event) => event.type == ChatEventType.toolStart).toList();
    final toolCompletes =
        events
            .where((event) => event.type == ChatEventType.toolComplete)
            .toList();
    final assistantText = events
        .where((event) => event.type == ChatEventType.assistantMessage)
        .map((event) => event.messageContent ?? '')
        .join('\n');

    if (toolStarts.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'id': item.id,
        'message': item.message,
        'expectedTool': item.expectedTool,
        'error': 'No tool call emitted.',
        'assistantText': assistantText,
      };
    }

    final firstTool = toolStarts.first;
    final complete = toolCompletes.isEmpty ? null : toolCompletes.first;
    final actualArgs = firstTool.toolArguments ?? <String, dynamic>{};
    final completeContent = complete?.toolResultContent ?? '';
    final argMismatches = <Map<String, Object?>>[];
    for (final entry in item.expectedArguments.entries) {
      if (!_argumentMatched(
        entry.key,
        entry.value,
        actualArgs,
        completeContent,
      )) {
        argMismatches.add(<String, Object?>{
          'key': entry.key,
          'expected': entry.value,
          'actual': actualArgs[entry.key],
        });
      }
    }
    final toolMatches = firstTool.toolName == item.expectedTool;
    final ok = toolMatches && argMismatches.isEmpty;
    return <String, Object?>{
      'ok': ok,
      'id': item.id,
      'message': item.message,
      'expectedTool': item.expectedTool,
      'actualTool': firstTool.toolName,
      'actualArguments': actualArgs,
      'toolResult': completeContent,
      if (!toolMatches) 'error': 'Wrong tool selected.',
      if (argMismatches.isNotEmpty) 'argumentMismatches': argMismatches,
      if (assistantText.isNotEmpty) 'assistantText': assistantText,
    };
  }

  static String? _argValue(List<String> args, String flagName) {
    final index = args.indexOf(flagName);
    if (index == -1) return null;
    if (index + 1 >= args.length) return null;
    final value = args[index + 1].trim();
    return value.isEmpty ? null : value;
  }

  static Set<String> _argValues(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>{};
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static _RealToolFixture _loadFixture(String path) {
    final decoded =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final context = decoded['runtimeContext'] as Map<String, Object?>;
    return _RealToolFixture(
      runtimeContext: ChatRuntimeContext(
        boardId: context['boardId'] as String?,
        boardName: context['boardName'] as String?,
        panelId: context['panelId'] as String?,
        panelTitle: context['panelTitle'] as String?,
      ),
      cases: (decoded['cases'] as List)
          .map((item) => _RealToolCase.fromJson(item as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  static Future<flm.InstalledModel> _loadInstalledModel(
    String? requestedId,
  ) async {
    final registryDir = await LocalModelRegistryLocator.resolveAsync();
    final registry = await sdk.ModelRegistry.loadDirectory(registryDir.path);
    final store = sdk.LocalModelStore(registry: registry);
    final installed = await store.listInstalledModels();
    final modelId = requestedId?.trim();
    final selected =
        modelId == null || modelId.isEmpty
            ? installed.firstWhere(
              (model) =>
                  model.manifest.tasks.contains(flm.ModelTask.chat) &&
                  (model.manifest.runtimeAdapter == flm.RuntimeAdapter.mlxLm ||
                      model.manifest.runtimeAdapter ==
                          flm.RuntimeAdapter.mlxVlm),
              orElse:
                  () =>
                      throw StateError('No installed local chat model found.'),
            )
            : installed.firstWhere(
              (model) => model.manifest.id == modelId,
              orElse:
                  () =>
                      throw StateError(
                        'Local chat model "$modelId" not found.',
                      ),
            );

    return flm.InstalledModel(
      manifest: selected.manifest,
      directory: selected.directory,
      sourceLabel: selected.sourceLabel,
      installedAt: selected.installedAt,
      sizeBytes: selected.sizeBytes,
      metadataUpdatedAt: selected.metadataUpdatedAt,
    );
  }

  static bool _argumentMatched(
    String key,
    Object? expected,
    Map<String, dynamic> actualArgs,
    String toolResult,
  ) {
    final actual = actualArgs[key];
    if (_looselyEqual(actual, expected)) {
      return true;
    }
    for (final alias in _aliasesFor(key)) {
      if (_looselyEqual(actualArgs[alias], expected)) {
        return true;
      }
    }
    final normalizedExpected = _normalize('$expected');
    return normalizedExpected.isNotEmpty &&
        _normalize(toolResult).contains(normalizedExpected);
  }

  static bool _looselyEqual(Object? actual, Object? expected) {
    if (actual == null) return false;
    return _normalize('$actual') == _normalize('$expected');
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'''["'`]+'''), '');
  }

  static List<String> _aliasesFor(String key) {
    return switch (key) {
      'board' => const <String>['id_or_name', 'board_id', 'board_name'],
      'id_or_name' => const <String>[
        'board',
        'id',
        'name',
        'board_id',
        'board_name',
      ],
      'panel' => const <String>['panel_id', 'panel_title'],
      'file_png' => const <String>['file', 'path', 'output'],
      'file_svg' => const <String>['file', 'path', 'output'],
      'new_name' => const <String>['new', 'name', 'newName'],
      'new_title' => const <String>['new', 'title', 'newTitle'],
      'card_id' => const <String>['cardId', 'id'],
      'to_column' => const <String>['to'],
      _ => const <String>[],
    };
  }
}

class _RealToolFixture {
  const _RealToolFixture({required this.runtimeContext, required this.cases});

  final ChatRuntimeContext runtimeContext;
  final List<_RealToolCase> cases;
}

class _RealToolCase {
  const _RealToolCase({
    required this.id,
    required this.category,
    required this.message,
    required this.expectedTool,
    required this.expectedArguments,
  });

  factory _RealToolCase.fromJson(Map<String, Object?> json) {
    return _RealToolCase(
      id: json['id'] as String,
      category: json['category'] as String? ?? 'general',
      message: json['message'] as String,
      expectedTool: json['expectedTool'] as String,
      expectedArguments: Map<String, Object?>.from(
        json['expectedArguments'] as Map,
      ),
    );
  }

  final String id;
  final String category;
  final String message;
  final String expectedTool;
  final Map<String, Object?> expectedArguments;
}
