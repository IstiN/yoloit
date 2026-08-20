import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/user_data_archive.dart';

/// Result of a `settings:export` call.
class ExportResult {
  const ExportResult({
    required this.path,
    required this.encrypted,
    required this.manifest,
  });

  final String path;
  final bool encrypted;
  final ArchiveManifest manifest;
}

/// Result of a `settings:import` call (dry-run or applied).
class ImportResult {
  const ImportResult({required this.report});

  final ImportReport report;
}

/// Thrown when the local CLI server isn't reachable (port file missing,
/// server not started, etc.). The UI surfaces this with a hint to launch
/// the desktop app first.
class BackupMigrationUnavailableError extends Error {
  BackupMigrationUnavailableError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// HTTP client for the /api/settings/{export,import} routes registered by
/// [CliServer]. Lives in the desktop process; talks to itself.
class BackupMigrationService {
  BackupMigrationService({http.Client? client, PlatformDirs? dirs})
    : _client = client ?? http.Client(),
      _dirs = dirs ?? PlatformDirs.instance;

  final http.Client _client;
  final PlatformDirs _dirs;

  Uri _endpoint(String route) {
    final portFile = File(p.join(_dirs.configDir, 'cli.port'));
    if (!portFile.existsSync()) {
      throw BackupMigrationUnavailableError(
        'YoLoIT CLI server is not running. '
        'Re-open the desktop app and try again.',
      );
    }
    final port = int.tryParse(portFile.readAsStringSync().trim());
    if (port == null) {
      throw BackupMigrationUnavailableError(
        'CLI port file is unreadable: ${portFile.path}',
      );
    }
    return Uri.parse('http://127.0.0.1:$port/api/settings/$route');
  }

  Future<ExportResult> export({
    required String destinationPath,
    required String passphrase,
    bool includeSecrets = false,
    bool includeHistory = true,
    bool includeChatSessions = true,
    bool includeCalendar = true,
    bool includeStateJson = true,
  }) async {
    final response = await _client.post(
      _endpoint('export'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'path': destinationPath,
        'passphrase': passphrase,
        'includeSecrets': includeSecrets,
        'includeHistory': includeHistory,
        'includeChatSessions': includeChatSessions,
        'includeCalendar': includeCalendar,
        'includeStateJson': includeStateJson,
        'requirePassphrase': passphrase.isNotEmpty,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['message']?.toString() ?? 'Export failed');
    }
    final payload = body['manifest'] as Map<String, dynamic>;
    return ExportResult(
      path: body['path'] as String,
      encrypted: body['encrypted'] as bool? ?? false,
      manifest: ArchiveManifest.fromJson(payload),
    );
  }

  Future<ImportResult> restore({
    required String archivePath,
    String? passphrase,
    bool dryRun = true,
    ImportMode mode = ImportMode.merge,
    PathRewriteStrategy pathRewrite = PathRewriteStrategy.auto,
    ImportOverrides overrides = ImportOverrides.defaults,
    BoardConflictChoice onConflict = BoardConflictChoice.keepBoth,
  }) async {
    final response = await _client.post(
      _endpoint('import'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'path': archivePath,
        'passphrase': passphrase,
        'dryRun': dryRun,
        'mode': mode.name,
        'pathRewrite': pathRewrite.name,
        'overrides': {
          'prefs': overrides.prefs,
          'config': overrides.config,
          'data': overrides.data,
          'workspaces': overrides.workspaces,
        },
        'onConflict': switch (onConflict) {
          BoardConflictChoice.overwrite => 'overwrite',
          BoardConflictChoice.renameIncoming => 'rename',
          BoardConflictChoice.skipIncoming => 'skip',
          BoardConflictChoice.keepBoth => 'keep',
        },
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['message']?.toString() ?? 'Import failed');
    }
    final reportJson = body['report'] as Map<String, dynamic>;
    return ImportResult(
      report: ImportReport.fromJson(reportJson),
    );
  }

  void close() => _client.close();
}
