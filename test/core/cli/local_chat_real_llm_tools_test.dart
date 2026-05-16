import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'built macOS app runs real local LLM tool oracle without UI',
    () async {
      if (Platform.environment['YOLOIT_REAL_LLM_TOOLS'] != '1') {
        return;
      }

      final executable =
          Platform.environment['YOLOIT_REAL_LLM_APP_EXECUTABLE'] ??
          'build/macos/Build/Products/Debug/YoLoIT (dev).app/Contents/MacOS/YoLoIT (dev)';
      if (!File(executable).existsSync()) {
        throw StateError(
          'Built app executable not found at "$executable". '
          'Run `flutter build macos --debug` or set YOLOIT_REAL_LLM_APP_EXECUTABLE.',
        );
      }

      final args = <String>[
        '--yoloit-real-llm-tool-test',
        Platform.environment['YOLOIT_REAL_LLM_TOOL_CASES_JSON'] ??
            'test/fixtures/local_chat_real_llm_tool_cases.json',
      ];
      final modelId = Platform.environment['YOLOIT_REAL_LLM_MODEL_ID'];
      if (modelId != null && modelId.trim().isNotEmpty) {
        args.addAll(<String>['--model-id', modelId.trim()]);
      }
      final caseLimit = Platform.environment['YOLOIT_REAL_LLM_TOOL_CASE_LIMIT'];
      if (caseLimit != null && caseLimit.trim().isNotEmpty) {
        args.addAll(<String>['--case-limit', caseLimit.trim()]);
      }
      final category =
          Platform.environment['YOLOIT_REAL_LLM_TOOL_CASE_CATEGORY'];
      if (category != null && category.trim().isNotEmpty) {
        args.addAll(<String>['--case-category', category.trim()]);
      }

      final result = await Process.run(
        executable,
        args,
        runInShell: false,
      ).timeout(const Duration(minutes: 35));

      final output = result.stdout.toString();
      final decoded = _decodeTrailingJson(output);
      expect(
        result.exitCode,
        0,
        reason: 'stderr:\n${result.stderr}\nstdout:\n$output',
      );
      expect(decoded['ok'], isTrue, reason: output);
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}

Map<String, Object?> _decodeTrailingJson(String output) {
  final start = output.indexOf('{');
  if (start == -1) {
    throw const FormatException('No JSON object found in runner output.');
  }
  return jsonDecode(output.substring(start)) as Map<String, Object?>;
}
