// covers: board:undo, board:redo

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI undo/redo', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'local-undo-redo-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_undo_redo');
      server = YoloitdServer(
        store: YoloitdStore(rootDir: tempDir, actorId: 'test'),
        host: '127.0.0.1',
        port: 0,
        token: token,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';
      cli = await YoloitCliHarness.create(baseUrl: baseUrl, token: token);
    });

    tearDown(() async {
      await cli.dispose();
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('undo and redo panel create cycle', () async {
      final boardName = 'CLI Undo Redo ${DateTime.now().millisecondsSinceEpoch}';
      await cli.json(['board:create', boardName]);

      final created = await cli.json([
        'panel:create',
        boardName,
        'board.note.markdown',
        'Undo Redo Note',
      ]);
      expect(created['ok'], isTrue);

      final panelsBefore = await cli.json(['panels', boardName]);
      final titlesBefore =
          (panelsBefore['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((panel) => panel['title'])
              .toList();
      expect(titlesBefore, contains('Undo Redo Note'));

      final undone = await cli.json(['board:undo', boardName]);
      expect(undone['ok'], isTrue);
      expect(undone['redoDepth'], 1);

      final panelsAfterUndo = await cli.json(['panels', boardName]);
      final titlesAfterUndo =
          (panelsAfterUndo['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((panel) => panel['title'])
              .toList();
      expect(titlesAfterUndo, isNot(contains('Undo Redo Note')));

      final redone = await cli.json(['board:redo', boardName]);
      expect(redone['ok'], isTrue);
      expect(redone['redoDepth'], 0);

      final panelsAfterRedo = await cli.json(['panels', boardName]);
      final titlesAfterRedo =
          (panelsAfterRedo['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((panel) => panel['title'])
              .toList();
      expect(titlesAfterRedo, contains('Undo Redo Note'));

      final emptyRedo = await cli.json(['board:redo', boardName]);
      expect(emptyRedo['ok'], isFalse);
    });

    test('redo clears after a new panel mutation', () async {
      final boardName =
          'CLI Redo Clear ${DateTime.now().millisecondsSinceEpoch}';
      await cli.json(['board:create', boardName]);
      await cli.json([
        'panel:create',
        boardName,
        'board.shape',
        'Redo Shape',
      ]);

      final undone = await cli.json(['board:undo', boardName]);
      expect(undone['ok'], isTrue);
      expect(undone['redoDepth'], 1);

      await cli.json([
        'panel:create',
        boardName,
        'board.sticky',
        'New sticky after undo',
      ]);

      final blockedRedo = await cli.json(['board:redo', boardName]);
      expect(blockedRedo['ok'], isFalse);
    });
  });
}
