import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Harness that drives the real `tools/yoloit` bash CLI against a remote
/// yoloitd daemon using an isolated `$HOME` directory.
class YoloitCliHarness {
  YoloitCliHarness({
    required this.baseUrl,
    required this.token,
    required this.homeDir,
  });

  final String baseUrl;
  final String token;
  final Directory homeDir;

  static Future<YoloitCliHarness> create({
    required String baseUrl,
    required String token,
  }) async {
    final homeDir = Directory(
      '${Directory.systemTemp.path}/yoloit_cli_${DateTime.now().microsecondsSinceEpoch}',
    );
    await homeDir.create(recursive: true);
    return YoloitCliHarness(
      baseUrl: baseUrl,
      token: token,
      homeDir: homeDir,
    );
  }

  Future<void> dispose() async {
    if (await homeDir.exists()) {
      await homeDir.delete(recursive: true);
    }
  }

  static String _shellEscape(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'^[A-Za-z0-9_\-+=.,/:@]+$').hasMatch(arg)) {
      return arg;
    }
    return "'${arg.replaceAll("'", "'\\''")}'";
  }

  /// Runs a `yoloit` command and returns the raw process result.
  Future<ProcessResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final script = File('${Directory.current.path}/tools/yoloit');
    if (!await script.exists()) {
      fail('tools/yoloit not found at ${script.path}');
    }
    final command = <String>[
      _shellEscape(script.path),
      ...args.map(_shellEscape),
    ].join(' ');
    final process = await Process.start(
      'bash',
      <String>['-c', command],
      environment: <String, String>{
        'HOME': homeDir.path,
        'YOLOIT_REMOTE_URL': baseUrl,
        'YOLOIT_REMOTE_TOKEN': token,
        'PATH': Platform.environment['PATH'] ?? '',
      },
      workingDirectory: Directory.current.path,
    );
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('yoloit ${args.join(' ')} timed out');
      },
    );
    return ProcessResult(
      process.pid,
      exitCode,
      await stdoutFuture,
      await stderrFuture,
    );
  }

  /// Runs a command and returns the parsed JSON output, or fails.
  Future<Map<String, dynamic>> json(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await run(args, timeout: timeout);
    if (result.exitCode != 0) {
      fail(
        'yoloit ${args.join(' ')} exited ${result.exitCode}\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }
    final text = (result.stdout as String).trim();
    if (text.isEmpty) {
      fail('yoloit ${args.join(' ')} produced empty output');
    }
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (error) {
      fail(
        'yoloit ${args.join(' ')} output is not JSON: $text\nerror: $error',
      );
    }
  }
}
