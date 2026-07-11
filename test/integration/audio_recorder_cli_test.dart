// covers: audio:start, audio:stop, audio:list, audio:set-folder, audio:transcribe

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI - audio recorder commands', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_audio');
      server = YoloitdServer(
        store: YoloitdStore(rootDir: tempDir, actorId: 'test'),
        host: '127.0.0.1',
        port: 0,
        token: 'local-audio-secret',
      );
      await server.start();
      cli = await YoloitCliHarness.create(
        baseUrl: 'http://127.0.0.1:${server.boundPort}',
        token: 'local-audio-secret',
      );
    });

    tearDown(() async {
      await cli.dispose();
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('registry lists the audio recorder commands', () async {
      // `help --format registry` is served entirely from the embedded CLI
      // registry (no running app required), so this is deterministic.
      final result = await cli.run(['help', '--format', 'registry']);
      expect(result.exitCode, 0, reason: result.stderr as String?);
      final entries =
          (jsonDecode(result.stdout as String) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .toList();
      final byName = <String, Map<String, dynamic>>{
        for (final e in entries) e['name'] as String: e,
      };
      for (final name in const [
        'audio:start',
        'audio:stop',
        'audio:list',
        'audio:set-folder',
        'audio:transcribe',
      ]) {
        expect(byName, contains(name), reason: 'missing $name in registry');
        expect(byName[name]!['group'], 'audio');
        expect((byName[name]!['description'] as String).isNotEmpty, isTrue);
      }
    });

    test('audio:set-folder requires a folder argument', () async {
      // The argument guard runs before any server contact, proving the bash
      // case branch exists and routes correctly.
      final result = await cli.run(['audio:set-folder']);
      expect(result.exitCode, isNot(0));
      expect(result.stderr as String, contains('audio:set-folder'));
    });

    test('audio commands route to the board audio panel', () async {
      await cli.json(['board:create', 'Audio Board']);

      // No audio panel exists yet on the board, so the handler reports the
      // guidance and exits non-zero WITHOUT attempting to start native capture.
      final result = await cli.run(['audio:list', 'Audio Board']);
      expect(result.exitCode, isNot(0));
      expect(result.stderr as String, contains('audio recorder panel'));
    });

    test('audio:transcribe routes to the board audio panel', () async {
      await cli.json(['board:create', 'Transcribe Board']);

      // No audio panel exists yet, so the CLI resolves the panel by type and
      // fails with the guidance BEFORE any ASR backend is invoked. This keeps
      // the test routing/registry-level only (no API keys, no whisper model).
      final result = await cli.run(['audio:transcribe', 'Transcribe Board']);
      expect(result.exitCode, isNot(0));
      expect(result.stderr as String, contains('audio recorder panel'));
    });
  });
}
