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
  });
}
