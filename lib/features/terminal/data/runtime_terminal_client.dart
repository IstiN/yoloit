import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show
        kDebugMode,
        ValueNotifier,
        protected,
        visibleForOverriding,
        visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:yoloit/features/terminal/data/runtime_paths.dart';

class RuntimeSessionCreateResult {
  const RuntimeSessionCreateResult({
    required this.existing,
    required this.shellPid,
  });

  final bool existing;
  final int shellPid;
}

class RuntimeTerminalClient {
  RuntimeTerminalClient({String? runtimeHome})
    : runtimeHome = runtimeHome ?? RuntimePaths.home;

  final String runtimeHome;
  final HttpClient _http = HttpClient();
  int? _port;

  /// Water marks (in bytes of pending stream lines) for the session-stream
  /// backpressure in [streamSession]: pause the HTTP response above the high
  /// mark, resume below the low mark.
  static const _streamHighWatermarkBytes = 256 * 1024;
  static const _streamLowWatermarkBytes = 64 * 1024;

  String get _portPath => '$runtimeHome/runtime.port';
  String get _pidPath => '$runtimeHome/runtime.pid';

  /// Notifies when a new yoloitd binary is bundled but the currently
  /// running runtime process is still the old one.
  static final ValueNotifier<bool> updateRequired = ValueNotifier(false);

  /// Test hook: overrides [kDebugMode] so release-only code paths
  /// (binary extraction, update checks) can be exercised in tests.
  @visibleForTesting
  static bool? debugModeOverride;

  bool get _isDebug => debugModeOverride ?? kDebugMode;

  Future<void> ensureStarted() async {
    if (_isDebug) {
      await _killStaleDebugRuntime();
    }
    if (await _loadPort() && await _isHealthy()) {
      await _checkBinaryUpdate();
      return;
    }
    await startRuntime();
    for (var i = 0; i < 50; i++) {
      if (await _loadPort() && await _isHealthy()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('YoLoIT runtime did not start');
  }

  Future<void> _checkBinaryUpdate() async {
    if (_isDebug) return;
    final binaryName = Platform.isWindows ? 'yoloitd.exe' : 'yoloitd';
    final installed = File('$runtimeHome/$binaryName');
    if (!await installed.exists()) return;
    try {
      final assetData = await rootBundle.load('tools/yoloitd/$binaryName');
      final assetBytes = assetData.buffer.asUint8List();
      if (await installed.length() != assetBytes.length) {
        updateRequired.value = true;
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _killPidFile(File pidFile, {int sigtermDelayMs = 300}) async {
    if (!await pidFile.exists()) return;
    final pidStr = (await pidFile.readAsString()).trim();
    final pid = int.tryParse(pidStr);
    if (pid == null) return;
    try {
      Process.killPid(pid, ProcessSignal.sigterm);
      await Future<void>.delayed(Duration(milliseconds: sigtermDelayMs));
      final check = await Process.run('kill', ['-0', '$pid']);
      if (check.exitCode == 0) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    } catch (_) {
      // ignore
    }
  }

  /// Kills the current runtime, re-extracts the binary, and starts a fresh one.
  Future<void> restartRuntime() async {
    await _killPidFile(File(_pidPath), sigtermDelayMs: 500);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _deleteIfExists(_portPath);
    await _deleteIfExists(_pidPath);

    // Re-extract binary and start fresh.
    await _runtimeBinaryPath();
    await startRuntime();
    for (var i = 0; i < 50; i++) {
      if (await _loadPort() && await _isHealthy()) {
        updateRequired.value = false;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('YoLoIT runtime did not restart');
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
    await _killPidFile(File(_pidPath));

    await _deleteIfExists(_portPath);
    await _deleteIfExists(_pidPath);
    await mtimeFile.writeAsString('$currentMtime');
  }

  Future<RuntimeSessionCreateResult> createSession({
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
    final session = response['session'];
    var shellPid = 0;
    if (session is Map) {
      final rawPid = session['pid'];
      shellPid =
          rawPid is int ? rawPid : int.tryParse(rawPid?.toString() ?? '') ?? 0;
    }
    return RuntimeSessionCreateResult(
      existing: response['existing'] == true,
      shellPid: shellPid,
    );
  }

  Stream<String> streamSession(String sessionId) async* {
    await ensureStarted();

    // Sequence number of the last event delivered to the consumer. On a
    // reconnect we pass it as ?since=N so the runtime replays only newer
    // events — a full replay would duplicate already-rendered output and
    // corrupt the terminal screen. Runtimes older than the seq protocol
    // neither send seq nor understand since: lastSeq stays null and the
    // behavior degrades to today's full replay (no worse than before).
    int? lastSeq;
    while (true) {
      try {
        final query = lastSeq != null ? '?since=$lastSeq' : '';
        final request = await _http.getUrl(
          _uri('/sessions/$sessionId/stream$query'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode == 404) {
          // Session does not exist anymore — truly ended.
          return;
        }
        if (response.statusCode != 200) {
          throw StateError('Runtime stream failed: HTTP ${response.statusCode}');
        }
        // Manual subscription with water-mark backpressure: when the consumer
        // falls behind (UI busy), pause the HTTP response so unread output
        // stays in the socket buffer / on the runtime side instead of growing
        // Dart-side queues without bound.
        final controller = StreamController<String>();
        var pendingBytes = 0;
        var pausedForBackpressure = false;
        late final StreamSubscription<String> sub;
        sub = response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            pendingBytes += line.length;
            controller.add(line);
            if (!pausedForBackpressure &&
                pendingBytes > _streamHighWatermarkBytes) {
              pausedForBackpressure = true;
              sub.pause();
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        try {
          await for (final line in controller.stream) {
            pendingBytes -= line.length;
            if (pausedForBackpressure &&
                pendingBytes < _streamLowWatermarkBytes) {
              pausedForBackpressure = false;
              sub.resume();
            }
            if (line.trim().isEmpty) continue;
            final event = jsonDecode(line) as Map<String, dynamic>;
            final seq = event['seq'];
            if (seq is int) {
              // Defensive dedupe: never deliver the same event twice, even
              // around the replay/live boundary of a fresh connection.
              if (seq <= (lastSeq ?? 0)) continue;
              lastSeq = seq;
            }
            if (event['type'] == 'output') {
              yield event['data'] as String? ?? '';
            }
            if (event['type'] == 'exit') {
              return;
            }
          }
        } finally {
          await sub.cancel();
        }
      } on StateError catch (e) {
        if (e.toString().contains('404')) {
          return;
        }
        rethrow;
      }

      // The HTTP stream closed without an exit event. This can happen when the
      // OS drops idle connections (e.g. App Nap) or during brief network gaps.
      // Wait a moment and attempt one reconnect if the runtime is still alive.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!await _isHealthy()) {
        // Runtime is gone (and likely restarted), so the session is dead.
        return;
      }
      // Otherwise loop around and re-attach to the stream.
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

  @protected
  @visibleForOverriding
  Future<void> startRuntime() async {
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

    await rotateLogIfNeeded('$runtimeHome/runtime.log');

    await Process.run('sh', [
      '-c',
      r'nohup "$1" --home "$2" >> "$2/runtime.log" 2>&1 < /dev/null &',
      'yoloit-runtime',
      binary,
      runtimeHome,
    ]);
  }

  /// Rotates the runtime log when it has grown past [maxBytes]: the current
  /// file becomes `runtime.log.old` (overwriting a previous rotation) and the
  /// daemon starts appending to a fresh file. Unbounded per-event logging
  /// (e.g. a flood of terminal output) once produced multi-GB logs.
  @visibleForTesting
  static Future<void> rotateLogIfNeeded(
    String logPath, {
    int maxBytes = 50 * 1024 * 1024,
  }) async {
    try {
      final log = File(logPath);
      if (!await log.exists()) return;
      if (await log.length() <= maxBytes) return;
      final old = File('$logPath.old');
      if (await old.exists()) {
        await old.delete();
      }
      await log.rename(old.path);
    } catch (_) {
      // Log rotation must never block runtime startup.
    }
  }

  Future<String> _runtimeBinaryPath() async {
    final binaryName = Platform.isWindows ? 'yoloitd.exe' : 'yoloitd';

    // In debug mode prefer the live binary in the project tree so developers
    // can iterate without rebuilding Flutter assets.
    if (_isDebug) {
      final debugPath = 'tools/yoloitd/$binaryName';
      if (await File(debugPath).exists()) return debugPath;
    }

    final installed = File('$runtimeHome/$binaryName');
    final assetData = await rootBundle.load('tools/yoloitd/$binaryName');
    final bytes = assetData.buffer.asUint8List();

    // Re-extract if missing or different size (cheap proxy for "outdated").
    if (!await installed.exists() || await installed.length() != bytes.length) {
      await installed.parent.create(recursive: true);
      await installed.writeAsBytes(bytes, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', installed.path]);
      }
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
