import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';

void main() {
  late Directory tempDir;
  late File callLog;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yoloit_tmux_test');
    callLog = File('${tempDir.path}/tmux_calls.log');
  });

  tearDown(() async {
    TmuxService.instance.tmuxBinForTesting = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Writes an executable shell script that records its arguments to
  /// [callLog] and emulates `list-sessions` output.
  Future<String> installFakeTmux({
    List<String> sessions = const [],
    int exitCode = 0,
  }) async {
    final script = File('${tempDir.path}/tmux-fake');
    final buffer = StringBuffer()
      ..writeln('#!/bin/sh')
      ..writeln('printf \'%s\\n\' "\$*" >> "${callLog.path}"');
    if (exitCode != 0) {
      buffer.writeln('exit $exitCode');
    } else {
      buffer
        ..writeln("if [ \"\$1\" = 'list-sessions' ]; then")
        ..writeln("  printf '${sessions.join('\\n')}\\n'")
        ..writeln('fi')
        ..writeln('exit 0');
    }
    await script.writeAsString(buffer.toString());
    await Process.run('chmod', ['+x', script.path]);
    return script.path;
  }

  Future<List<String>> loggedCalls() async {
    if (!await callLog.exists()) return const [];
    final content = await callLog.readAsString();
    return content.split('\n').where((line) => line.isNotEmpty).toList();
  }

  group('TmuxService.listSessions', () {
    test('returns empty list when tmux binary is not configured', () async {
      TmuxService.instance.tmuxBinForTesting = null;
      expect(await TmuxService.instance.listSessions(), isEmpty);
    });

    test('parses session names and drops empty lines', () async {
      final bin = await installFakeTmux(sessions: ['alpha', 'beta']);
      TmuxService.instance.tmuxBinForTesting = bin;

      expect(await TmuxService.instance.listSessions(), ['alpha', 'beta']);
    });

    test('returns empty list when tmux exits non-zero', () async {
      final bin = await installFakeTmux(exitCode: 1);
      TmuxService.instance.tmuxBinForTesting = bin;

      expect(await TmuxService.instance.listSessions(), isEmpty);
    });

    test('returns empty list when the binary cannot be started', () async {
      TmuxService.instance.tmuxBinForTesting =
          '${tempDir.path}/does-not-exist';

      expect(await TmuxService.instance.listSessions(), isEmpty);
    });
  });

  group('TmuxService.injectEnv', () {
    test('does nothing when env is empty', () async {
      final bin = await installFakeTmux();
      TmuxService.instance.tmuxBinForTesting = bin;

      await TmuxService.instance.injectEnv('sess', const {});

      expect(await loggedCalls(), isEmpty);
    });

    test('does nothing when tmux binary is not configured', () async {
      TmuxService.instance.tmuxBinForTesting = null;

      await TmuxService.instance.injectEnv('sess', const {'A': '1'});

      expect(await callLog.exists(), isFalse);
    });

    test('sets each variable and re-exports without leaking values', () async {
      final bin = await installFakeTmux();
      TmuxService.instance.tmuxBinForTesting = bin;

      await TmuxService.instance.injectEnv('my sess!', const {
        'API_KEY': 'supersecret',
        'PLAIN': 'value',
      });

      final calls = await loggedCalls();
      // Session name is sanitised for tmux.
      expect(
        calls,
        containsAll([
          'setenv -t my_sess_ API_KEY supersecret',
          'setenv -t my_sess_ PLAIN value',
        ]),
      );
      final sendKeys = calls.singleWhere((c) => c.startsWith('send-keys'));
      expect(
        sendKeys,
        'send-keys -t my_sess_ '
        'eval "\$(tmux show-environment -s -t my_sess_)" Enter',
      );
      // The re-export must reference tmux's environment, never the values.
      expect(sendKeys, isNot(contains('supersecret')));
    });
  });
}
