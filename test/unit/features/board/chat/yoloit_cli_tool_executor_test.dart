import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

void main() {
  group('YoloitCliToolExecutor smart board args', () {
    test('omits board when panel omitted for checklist smart-parse', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'chck',
        <String, Object?>{'item': 'Buy milk'},
        runtimeContext: const ChatRuntimeContext(
          boardId: 'board-1',
          boardName: 'My Board',
          panelId: 'chat-1',
          panelTitle: 'Chat',
          panelType: 'board.chat',
        ),
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['command'], "yoloit checklist:check 'Buy milk'");
      expect((decoded['command'] as String), isNot(contains('board-1')));
    });

    test('includes board and panel when both provided', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'chck',
        <String, Object?>{
          'board': 'board-1',
          'panel': 'Shopping',
          'item': 'Buy milk',
        },
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(
        decoded['command'],
        "yoloit checklist:check board-1 Shopping 'Buy milk'",
      );
    });
  });

  group('YoloitCliToolArgumentNormalizer', () {
    test('does not redirect panel:help without user message', () {
      expect(
        YoloitCliToolArgumentNormalizer.normalizeFunctionName(
          functionName: 'yoloit_panel_help',
          userMessage: '',
        ),
        'yoloit_panel_help',
      );
    });

    test('redirects note set to note:create for English create phrasing', () {
      for (final message in [
        'please create a note for me',
        'make a note about milk',
        'new note with ideas',
      ]) {
        expect(
          YoloitCliToolArgumentNormalizer.normalizeFunctionName(
            functionName: 'yoloit_note',
            userMessage: message,
          ),
          'ncrt',
          reason: message,
        );
      }
    });

    test('redirects note set to note:create for Russian phrasing', () {
      for (final message in [
        'создай заметку про планы',
        'сделай заметку',
        'добавь заметку к доске',
        'покажи новая заметка',
      ]) {
        expect(
          YoloitCliToolArgumentNormalizer.normalizeFunctionName(
            functionName: 'yoloit_note',
            userMessage: message,
          ),
          'ncrt',
          reason: message,
        );
      }
    });

    test('redirects note aliases nst and note to note:create', () {
      for (final functionName in ['nst', 'note']) {
        expect(
          YoloitCliToolArgumentNormalizer.normalizeFunctionName(
            functionName: functionName,
            userMessage: 'create note with todos',
          ),
          'ncrt',
          reason: functionName,
        );
      }
    });

    test('keeps note set when the user does not ask for a new note', () {
      expect(
        YoloitCliToolArgumentNormalizer.normalizeFunctionName(
          functionName: 'yoloit_note',
          userMessage: 'update the note text',
        ),
        'yoloit_note',
      );
    });

    test('ignores create-note phrasing for unrelated functions', () {
      expect(
        YoloitCliToolArgumentNormalizer.normalizeFunctionName(
          functionName: 'yoloit_sticky_set',
          userMessage: 'create a note please',
        ),
        'yoloit_sticky_set',
      );
    });
  });

  group('YoloitCliToolExecutor invoke', () {
    test('returns early error for unknown tool', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke('nope_tool', const {});
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Unknown YoLoIT tool'));
    });

    test('list_tools returns the compact catalog without execution', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke('list_tools', const {});
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['tools'], isA<List<dynamic>>());
    });

    test('reports missing required parameter', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pmk',
        <String, Object?>{'board': 'b1', 'type': 'board.sticky'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['executed'], isFalse);
      expect(decoded['error'], contains('Missing required "title"'));
    });

    test('rejects placeholder ids during validation', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pdl',
        <String, Object?>{'board': 'b1', 'panel': 'yoloit_panel_42'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['executed'], isFalse);
      expect(decoded['error'], contains('placeholder id'));
    });

    test('rejects non-numeric values for number parameters', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pmv',
        <String, Object?>{
          'board': 'b1',
          'panel': 'p1',
          'x': 'abc',
          'y': '2',
        },
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('must be a number'));
    });

    test('rejects values outside the enum set', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pmk',
        <String, Object?>{
          'board': 'b1',
          'type': 'board.nope',
          'title': 'T',
        },
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Invalid value for "type"'));
    });

    test('blocks destructive commands without confirmation', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pdl',
        <String, Object?>{'board': 'b1', 'panel': 'p1'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['executed'], isFalse);
      expect(decoded['error'], contains('requires confirm=true'));
    });

    test('dry-runs a confirmed destructive command', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'pdl',
        <String, Object?>{'board': 'b1', 'panel': 'p1', 'confirm': true},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['executed'], isFalse);
      expect(decoded['command'], 'yoloit panel:delete b1 p1');
    });

    test('dry-runs through the full normalization path', () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result = await executor.invoke(
        'yoloit_panel_create',
        <String, Object?>{
          'board': 'b1',
          'type': 'board.sticky',
          'title': 'My Sticky',
        },
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['executed'], isFalse);
      expect(decoded['command'], "yoloit panel:create b1 board.sticky 'My Sticky'");
    });

    test('executes board:apply with inline yaml via a temp file', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/echo');
      final result = await executor.invoke(
        'bap',
        <String, Object?>{'id_or_name': 'b1', 'yaml': 'panels: []'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['exitCode'], 0);
      expect(decoded['command'], contains('board:apply b1'));
    });

    test('executes board:apply with a file argument unchanged', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/echo');
      final result = await executor.invoke(
        'bap',
        <String, Object?>{'id_or_name': 'b1', 'file': 'spec.yaml'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['exitCode'], 0);
      expect(decoded['command'], 'yoloit board:apply b1 spec.yaml');
    });

    test('wraps a failing process exit code', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/usr/bin/false');
      final result = await executor.invoke(
        'pls',
        <String, Object?>{'board': 'b1'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['exitCode'], 1);
    });

    test('captures stderr from the subprocess', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/ls');
      final result = await executor.invoke(
        'pls',
        <String, Object?>{'board': 'b1'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['stderr'], isA<String>());
      expect((decoded['stderr'] as String), isNotEmpty);
    });
  });
}
