import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/setup/setup_catalog.dart';

/// Shared JSON/HTML response helpers for YoLoIT remote servers.

Future<Map<String, dynamic>> readJsonBody(shelf.Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(text);
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return <String, dynamic>{};
}

shelf.Response jsonResponse(Object? body, [int statusCode = 200]) {
  return shelf.Response(
    statusCode,
    body: jsonEncode(body),
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

shelf.Response htmlResponse(String body) {
  return shelf.Response.ok(
    body,
    headers: const <String, String>{
      'content-type': 'text/html; charset=utf-8',
    },
  );
}

/// Shared file-system helpers.

String? homePath() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final trimmed = home?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

bool validDirectoryName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return false;
  return !name.contains('/') && !name.contains('\\') && !name.contains('\x00');
}

String shellQuote(String value) =>
    "'${value.replaceAll("'", "'\\''")}'";

/// Shared process helpers.

Future<String?> findExecutable(String name) async {
  final result = await Process.run(
    Platform.environment['SHELL'] ?? '/bin/sh',
    <String>['-lc', 'command -v ${shellQuote(name)}'],
  );
  if (result.exitCode != 0) return null;
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path.split('\n').first.trim();
}

Future<({String executable, List<String> arguments})> terminalLauncher(
  String shell,
) async {
  final script =
      (Platform.isLinux || Platform.isMacOS) ? await findExecutable('script') : null;
  if (script != null) {
    if (Platform.isMacOS) {
      return (
        executable: script,
        arguments: <String>['-q', '/dev/null', shell, '-i'],
      );
    }
    return (
      executable: script,
      arguments: <String>['-q', '-f', '-c', shell, '/dev/null'],
    );
  }
  return (executable: shell, arguments: <String>['-i']);
}

/// Shared process/terminal/run state and lifecycle logic used by both
/// [BoardShareServer] and [YoloitdServer].
///
/// The host class is responsible for exposing the state maps via the abstract
/// getters and for any server-specific request routing.
mixin ServerProcessMixin {
  final Map<String, Process> runs = <String, Process>{};
  final Set<String> activeTaskRuns = <String>{};
  final Map<String, List<String>> runLogs = <String, List<String>>{};
  final Map<String, int> runExitCodes = <String, int>{};
  final Map<String, Process> terminals = <String, Process>{};
  final Map<String, List<String>> terminalChunks = <String, List<String>>{};
  final Map<String, int> terminalExitCodes = <String, int>{};

  void killAllRunsAndTerminals() {
    for (final process in runs.values) {
      process.kill();
    }
    runs.clear();
    activeTaskRuns.clear();
    for (final process in terminals.values) {
      process.kill();
    }
    terminals.clear();
  }

  Future<void> collectTerminal(String id, Process process) async {
    void add(String chunk) {
      final chunks = terminalChunks[id] ??= <String>[];
      chunks.add(chunk);
      if (chunks.length > 2000) chunks.removeRange(0, chunks.length - 2000);
    }

    process.stdout.transform(utf8.decoder).listen(add);
    process.stderr.transform(utf8.decoder).listen(add);
    final exitCode = await process.exitCode;
    add('\n[exit $exitCode]\n');
    terminals.remove(id);
    terminalExitCodes[id] = exitCode;
  }

  Future<void> collectRun(String id, Process process) async {
    void add(String line) {
      final lines = runLogs[id] ??= <String>[];
      lines.add(line);
      if (lines.length > 1000) lines.removeRange(0, lines.length - 1000);
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(add);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(add);
    final exitCode = await process.exitCode;
    add('[exit $exitCode]');
    runs.remove(id);
    runExitCodes[id] = exitCode;
  }

  Future<void> runSetupInstallTasks(
    String id,
    List<String> specialIds,
    String script,
    String workingDirectory,
  ) async {
    final lines = runLogs[id] ??= <String>[];
    var exitCode = 0;
    try {
      for (final specialId in specialIds) {
        await for (final line in SetupCatalog.runSpecialInstallTask(specialId)) {
          lines.add(line);
        }
      }
      if (script.trim().isNotEmpty) {
        final process = await Process.start(
          Platform.environment['SHELL'] ?? '/bin/sh',
          <String>['-lc', script],
          workingDirectory: workingDirectory,
        );
        runs[id] = process;
        await collectRun(id, process);
        return;
      }
    } catch (error) {
      exitCode = 1;
      lines.add('[error] $error');
    } finally {
      activeTaskRuns.remove(id);
      if (!runExitCodes.containsKey(id)) {
        runExitCodes[id] = exitCode;
        lines.add('[exit $exitCode]');
      }
    }
  }

  /// Shared handler for `/api/setup` including the install POST and the log GET.
  Future<shelf.Response> handleSetupRequest({
    required shelf.Request request,
    required String method,
    required List<String> sub,
    required String Function() nextId,
    required Future<void> Function(String id, List<String> specialIds, String script)
        startTasks,
  }) async {
    if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
      return jsonResponse(<String, Object?>{
        'id': sub[0],
        'lines': runLogs[sub[0]] ?? const <String>[],
        'running':
            runs.containsKey(sub[0]) || activeTaskRuns.contains(sub[0]),
        if (runExitCodes.containsKey(sub[0])) 'exitCode': runExitCodes[sub[0]],
      });
    }
    return handleSetupInstall(
      request: request,
      method: method,
      sub: sub,
      nextId: nextId,
      onStarted: (id, displayScript) {
        runLogs[id] = <String>['\$ $displayScript'];
        runExitCodes.remove(id);
        activeTaskRuns.add(id);
      },
      startTasks: startTasks,
    );
  }
}

/// Shared file-listing response helper.
///
/// [entries] and [roots] are provided by the caller because the two servers
/// build them using slightly different directory helpers.
Future<shelf.Response> buildFileListingResponse({
  required Directory directory,
  required List<Map<String, Object?>> entries,
  required List<Map<String, Object?>> roots,
}) async {
  if (!await directory.exists()) {
    return jsonResponse(<String, Object?>{
      'ok': false,
      'error': 'directory not found',
      'path': directory.path,
    }, 404);
  }

  return jsonResponse(<String, Object?>{
    'ok': true,
    'path': directory.path,
    'parent':
        directory.parent.path == directory.path ? null : directory.parent.path,
    'roots': roots,
    'entries': entries,
  });
}

/// Shared handler for `POST /api/setup/install`.
///
/// [nextId] generates a run identifier. [startTasks] begins the asynchronous
/// install work using the server-specific working directory.
Future<shelf.Response> handleSetupInstall({
  required shelf.Request request,
  required String method,
  required List<String> sub,
  required String Function() nextId,
  required void Function(String id, String displayScript) onStarted,
  required Future<void> Function(String id, List<String> specialIds, String script)
      startTasks,
}) async {
  if (sub.isEmpty && method == 'GET') {
    final snapshot = await SetupCatalog.check();
    return jsonResponse(snapshot.toJson());
  }
  if (sub.length == 1 && sub[0] == 'install' && method == 'POST') {
    final body = await readJsonBody(request);
    final ids =
        (body['packageIds'] as List? ?? const <Object?>[])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();
    if (ids.isEmpty) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'packageIds required',
      }, 400);
    }
    final runtime = await SetupCatalog.detectRuntime();
    final specialIds = ids.where(SetupCatalog.isSpecialInstallTask).toList()..sort();
    final script = SetupCatalog.installScript(ids, runtime.os);
    if (script.trim().isEmpty && specialIds.isEmpty) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'no install command for selected packages on this OS',
      }, 400);
    }
    final displayScript = <String>[
      for (final id in specialIds) SetupCatalog.specialInstallLabel(id),
      if (script.trim().isNotEmpty) script,
    ].join('\n');
    if (body['dryRun'] == true) {
      return jsonResponse(<String, Object?>{'ok': true, 'script': displayScript});
    }
    final id = body['id'] as String? ?? nextId();
    onStarted(id, displayScript);
    unawaited(startTasks(id, specialIds, script));
    return jsonResponse(<String, Object?>{
      'ok': true,
      'id': id,
      'script': displayScript,
    });
  }
  return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
}

/// Shared handler for `POST /api/files/directories`.
///
/// Creates a new directory under [parentPath] (or the [defaultRoot] if empty)
/// and returns a refreshed file listing via [listFiles].
Future<shelf.Response> handleCreateDirectory({
  required shelf.Request request,
  required String Function() defaultRoot,
  required Future<shelf.Response> Function(String path) listFiles,
}) async {
  final body = await readJsonBody(request);
  final parentPath = (body['parentPath'] as String? ?? '').trim();
  final name = (body['name'] as String? ?? '').trim();
  if (!validDirectoryName(name)) {
    return jsonResponse(<String, Object?>{
      'ok': false,
      'error': 'invalid directory name',
    }, 400);
  }
  final parent = Directory(
    parentPath.isEmpty ? defaultRoot() : parentPath,
  );
  if (!await parent.exists()) {
    return jsonResponse(<String, Object?>{
      'ok': false,
      'error': 'parent directory not found',
      'path': parent.path,
    }, 404);
  }
  await Directory('${parent.path}${Platform.pathSeparator}$name').create();
  return listFiles(parent.path);
}

/// Shared builder for `GET /api/terminals/{id}/log` responses.
shelf.Response terminalLogResponse({
  required String id,
  required int since,
  required List<String> chunks,
  required bool running,
  required int? exitCode,
}) {
  final start = since.clamp(0, chunks.length);
  return jsonResponse(<String, Object?>{
    'id': id,
    'next': chunks.length,
    'chunks': chunks.skip(start).toList(),
    'running': running,
    if (exitCode case final int value) 'exitCode': value,
  });
}

/// Shared handler for `POST /api/terminals`.
///
/// Validates the request, picks the working directory, parses the environment,
/// resolves the shell launcher, and starts the terminal process. The caller is
/// responsible for storing the process and starting log collection.
Future<shelf.Response> handleTerminalCreate({
  required shelf.Request request,
  required String defaultCwd,
  required String Function() nextId,
  required void Function(String id) killExisting,
  required void Function(String id, Process process) onProcessStarted,
}) async {
  final body = await readJsonBody(request);
  final id = (body['id'] as String? ?? nextId()).trim();
  final cwd = (body['cwd'] as String? ?? defaultCwd).trim();
  if (id.isEmpty) {
    return jsonResponse(
      <String, Object?>{'ok': false, 'error': 'id required'},
      400,
    );
  }
  final directory = Directory(cwd.isEmpty ? defaultCwd : cwd);
  if (!await directory.exists()) {
    return jsonResponse(
      <String, Object?>{
        'ok': false,
        'error': 'working directory not found',
        'path': directory.path,
      },
      404,
    );
  }
  killExisting(id);
  final rawEnv = body['env'];
  final env =
      rawEnv is Map
          ? rawEnv.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
          : const <String, String>{};
  final shell = Platform.environment['SHELL'] ?? '/bin/sh';
  final launcher = await terminalLauncher(shell);
  final process = await Process.start(
    launcher.executable,
    launcher.arguments,
    workingDirectory: directory.path,
    environment: <String, String>{
      'TERM': 'xterm-256color',
      if (env.isNotEmpty) ...env,
    },
  );
  onProcessStarted(id, process);
  return jsonResponse(
    <String, Object?>{'ok': true, 'id': id, 'pid': process.pid},
  );
}

/// Shared handler for `/api/files` routes.
///
/// [listFiles] must return a full file-listing response for an optional path.
Future<shelf.Response> handleFilesRequest({
  required shelf.Request request,
  required String method,
  required List<String> sub,
  required String Function() defaultRoot,
  required Future<shelf.Response> Function(String? path) listFiles,
}) async {
  if (sub.isEmpty && method == 'GET') {
    return listFiles(request.url.queryParameters['path']?.trim());
  }
  if (sub.length == 1 && sub[0] == 'directories' && method == 'POST') {
    return handleCreateDirectory(
      request: request,
      defaultRoot: defaultRoot,
      listFiles: listFiles,
    );
  }
  return jsonResponse(<String, Object?>{
    'ok': false,
    'error': 'method not allowed',
  }, 405);
}

/// Shared handler for `/api/terminals` routes.
Future<shelf.Response> handleTerminalsRequest({
  required shelf.Request request,
  required String method,
  required List<String> sub,
  required String defaultCwd,
  required String Function() nextId,
  required void Function(String id) killExisting,
  required void Function(String id, Process process) onProcessStarted,
  required Map<String, Process> terminals,
  required Map<String, List<String>> terminalChunks,
  required Map<String, int> terminalExitCodes,
}) async {
  if (sub.isEmpty && method == 'POST') {
    return handleTerminalCreate(
      request: request,
      defaultCwd: defaultCwd,
      nextId: nextId,
      killExisting: killExisting,
      onProcessStarted: onProcessStarted,
    );
  }
  if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
    final since =
        int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
    return terminalLogResponse(
      id: sub[0],
      since: since,
      chunks: terminalChunks[sub[0]] ?? const <String>[],
      running: terminals.containsKey(sub[0]),
      exitCode: terminalExitCodes[sub[0]],
    );
  }
  if (sub.length == 2 && sub[1] == 'input' && method == 'POST') {
    final process = terminals[sub[0]];
    if (process == null) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'terminal not found',
      }, 404);
    }
    final body = await readJsonBody(request);
    process.stdin.write(body['data'] as String? ?? '');
    await process.stdin.flush();
    return jsonResponse(<String, Object?>{'ok': true});
  }
  if (sub.length == 2 && sub[1] == 'resize' && method == 'POST') {
    final process = terminals[sub[0]];
    if (process == null) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'terminal not found',
      }, 404);
    }
    final body = await readJsonBody(request);
    final rows = (body['rows'] as num?)?.toInt() ?? 24;
    final cols = (body['cols'] as num?)?.toInt() ?? 80;
    process.stdin.write('stty rows $rows cols $cols\n');
    await process.stdin.flush();
    return jsonResponse(<String, Object?>{'ok': true});
  }
  if (sub.length == 2 && sub[1] == 'stop' && method == 'POST') {
    final process = terminals.remove(sub[0]);
    final ok = process?.kill() ?? false;
    return jsonResponse(<String, Object?>{'ok': ok});
  }
  return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
}

/// Returns `true` if the request carries the expected bearer/query token.
bool isAuthorized(shelf.Request request, String? token) {
  final expected = token?.trim();
  if (expected == null || expected.isEmpty) return true;
  final auth = request.headers['authorization'] ?? '';
  if (auth == 'Bearer $expected') return true;
  return request.url.queryParameters['token'] == expected;
}
