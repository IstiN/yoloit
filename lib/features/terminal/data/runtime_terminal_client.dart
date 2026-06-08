import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:yoloit/core/platform/platform_dirs.dart';

class RuntimeTerminalClient {
  RuntimeTerminalClient({String? runtimeHome})
    : runtimeHome =
          runtimeHome ??
          (kDebugMode
              ? _debugRuntimeHome()
              : '${PlatformDirs.instance.configDir}/runtime');

  final String runtimeHome;
  final HttpClient _http = HttpClient();
  int? _port;

  static String _debugRuntimeHome() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.config/yoloit-dev/runtime';
  }

  String get _portPath => '$runtimeHome/runtime.port';
  String get _pidPath => '$runtimeHome/runtime.pid';

  Future<void> ensureStarted() async {
    if (kDebugMode) {
      await _killStaleDebugRuntime();
    }
    if (await _loadPort() && await _isHealthy()) return;
    await _startRuntime();
    for (var i = 0; i < 50; i++) {
      if (await _loadPort() && await _isHealthy()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('YoLoIT runtime did not start');
  }

  Future<void> _killStaleDebugRuntime() async {
    final scriptPath = await _runtimeBinaryPath();
    final script = File(scriptPath);
    if (!await script.exists()) return;

    final mtimePath = '$runtimeHome/script.mtime';
    final currentMtime = (await script.lastModified()).millisecondsSinceEpoch;

    final mtimeFile = File(mtimePath);
    int? savedMtime;
    if (await mtimeFile.exists()) {
      savedMtime = int.tryParse(await mtimeFile.readAsString());
    }

    if (savedMtime == currentMtime) {
      // Script unchanged — keep existing runtime so sessions survive hot-restart.
      return;
    }

    // Script changed — kill stale runtime.
    final pidFile = File(_pidPath);
    if (await pidFile.exists()) {
      final pidStr = (await pidFile.readAsString()).trim();
      final pid = int.tryParse(pidStr);
      if (pid != null) {
        try {
          final result = await Process.run('kill', ['-0', '$pid']);
          if (result.exitCode == 0) {
            Process.killPid(pid, ProcessSignal.sigterm);
            await Future<void>.delayed(const Duration(milliseconds: 300));
            final check = await Process.run('kill', ['-0', '$pid']);
            if (check.exitCode == 0) {
              Process.killPid(pid, ProcessSignal.sigkill);
            }
          }
        } catch (_) {
          // ignore
        }
      }
    }

    await _deleteIfExists(_portPath);
    await _deleteIfExists(_pidPath);
    await mtimeFile.writeAsString('$currentMtime');
  }

  Future<bool> createSession({
    required String sessionId,
    required String cwd,
    String? command,
    Map<String, String> env = const {},
    int cols = 120,
    int rows = 30,
  }) async {
    final response = await _post('/sessions', {
      'id': sessionId,
      'cwd': cwd,
      if (command != null) 'command': command,
      'env': env,
      'cols': cols,
      'rows': rows,
    });
    return response['existing'] == true;
  }

  Stream<String> streamSession(String sessionId) async* {
    await ensureStarted();
    final request = await _http.getUrl(_uri('/sessions/$sessionId/stream'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('Runtime stream failed: HTTP ${response.statusCode}');
    }
    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = jsonDecode(line) as Map<String, dynamic>;
      if (event['type'] == 'output') {
        yield event['data'] as String? ?? '';
      }
      if (event['type'] == 'exit') return;
    }
  }

  Future<void> input(String sessionId, String data) async {
    await _post('/sessions/$sessionId/input', {
      'data': base64Encode(utf8.encode(data)),
    });
  }

  Future<void> resize(String sessionId, int cols, int rows) async {
    try {
      await _post('/sessions/$sessionId/resize', {'cols': cols, 'rows': rows});
    } on StateError catch (e) {
      if (e.toString().contains('404')) {
        // Session expired or runtime was restarted; ignore gracefully.
        return;
      }
      rethrow;
    }
  }

  Future<void> kill(String sessionId) async {
    await _post('/sessions/$sessionId/kill', {});
  }

  Future<bool> _loadPort() async {
    final file = File(_portPath);
    if (!await file.exists()) return false;
    final raw = (await file.readAsString()).trim();
    _port = int.tryParse(raw);
    return _port != null;
  }

  Future<bool> _isHealthy() async {
    try {
      final request = await _http.getUrl(_uri('/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startRuntime() async {
    final dir = Directory(runtimeHome);
    await dir.create(recursive: true);
    await _deleteIfExists(_portPath);
    await _deleteIfExists(_pidPath);

    final binary = await _runtimeBinaryPath();

    if (Platform.isWindows) {
      await Process.start(binary, [
        '--home',
        runtimeHome,
      ], mode: ProcessStartMode.detached);
      return;
    }

    await Process.run('sh', [
      '-c',
      r'nohup "$1" --home "$2" >> "$2/runtime.log" 2>&1 < /dev/null &',
      'yoloit-runtime',
      binary,
      runtimeHome,
    ]);
  }

  Future<String> _runtimeBinaryPath() async {
    final binaryName = Platform.isWindows ? 'yoloitd.exe' : 'yoloitd';
    final candidates = [
      'tools/yoloitd/$binaryName',
      '$runtimeHome/$binaryName',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    // Extract from bundled assets to runtimeHome
    final installed = File('$runtimeHome/$binaryName');
    final assetData = await rootBundle.load('tools/yoloitd/$binaryName');
    final bytes = assetData.buffer.asUint8List();
    await installed.parent.create(recursive: true);
    await installed.writeAsBytes(bytes, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', installed.path]);
    }
    return installed.path;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    await ensureStarted();
    final request = await _http.postUrl(_uri(path));
    final encodedBody = utf8.encode(jsonEncode(body));
    request.headers.contentType = ContentType.json;
    request.contentLength = encodedBody.length;
    request.add(encodedBody);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Runtime request failed: HTTP ${response.statusCode}');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Uri _uri(String path) {
    final port = _port;
    if (port == null) throw StateError('Runtime port is not loaded');
    return Uri.parse('http://127.0.0.1:$port$path');
  }
}
