import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/core/services/user_data_archive.dart';

/// Shared context for the /api/settings/... route family.
class _SettingsContext {
  const _SettingsContext({required this.request, required this.json});
  final shelf.Request request;
  final shelf.Response Function(Object) json;
}

typedef _SettingsRouteHandler = Future<shelf.Response> Function(
  _SettingsContext ctx,
);

class _SettingsRoute {
  const _SettingsRoute(this.method, this.segments, this.handler);

  final String method;
  final List<String> segments;
  final _SettingsRouteHandler handler;

  bool matches(String method, List<String> path) {
    if (this.method != method || path.length != segments.length) return false;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != path[i]) return false;
    }
    return true;
  }
}

final List<_SettingsRoute> _settingsRoutes = [
  const _SettingsRoute('POST', ['export'], _exportSettings),
  const _SettingsRoute('POST', ['import'], _importSettings),
];

Future<shelf.Response> handleSettings(
  String method,
  List<String> path,
  shelf.Request request, {
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) notFound,
  UserDataArchive? archive,
}) async {
  final ctx = _SettingsContext(request: request, json: json);
  for (final route in _settingsRoutes) {
    if (route.matches(method, path)) return route.handler(ctx);
  }
  return notFound(unknownRoute('settings'));
}

// POST /api/settings/export { path, includeSecrets, includeHistory,
// includeChatSessions, includeCalendar, includeStateJson,
// requirePassphrase }
Future<shelf.Response> _exportSettings(_SettingsContext ctx) async {
  final json = ctx.json;
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
  } catch (e) {
    return json(errorJson('Invalid JSON: $e'));
  }

  final dest = (body['path'] as String?)?.trim();
  if (dest == null || dest.isEmpty) {
    return json(errorJson('Provide "path" to write the archive to'));
  }

  final include = ArchiveIncludeOptions(
    secrets: body['includeSecrets'] == true,
    history: body['includeHistory'] != false,
    chatSessions: body['includeChatSessions'] != false,
    calendar: body['includeCalendar'] != false,
    stateJson: body['includeStateJson'] != false,
  );

  // Passphrase resolution order:
  //   1. body['passphrase']  (UI explicitly sends it)
  //   2. YOLOIT_ARCHIVE_PASSPHRASE env var  (CLI sets it before invoking)
  //   3. reject — encryption is mandatory unless requirePassphrase=false
  String? passphrase = body['passphrase'] as String?;
  if (passphrase == null || passphrase.isEmpty) {
    passphrase = Platform.environment['YOLOIT_ARCHIVE_PASSPHRASE'];
  }
  if (body['requirePassphrase'] != false) {
    if (passphrase == null || passphrase.isEmpty) {
      return json(
        errorJson(
          'Export requires a passphrase. Pass it via "passphrase" in the '
          'request body, set YOLOIT_ARCHIVE_PASSPHRASE in the environment, '
          'or set requirePassphrase=false to export without encryption.',
        ),
      );
    }
  }

  try {
    final svc = UserDataArchive();
    final manifest = await svc.pack(
      outputPath: dest,
      passphrase: passphrase,
      include: include,
    );
    return json(
      okJson({
        'path': dest,
        'encrypted': passphrase != null,
        'manifest': manifest.toJson(),
      }),
    );
  } catch (e) {
    return json(errorJson('Export failed: $e'));
  }
}

// POST /api/settings/import { path, dryRun, mode, pathRewrite, passphrase,
// overrides: { prefs, config, data, workspaces } }

const Map<String, ImportMode> _importModes = {
  'replace': ImportMode.replace,
  'merge': ImportMode.merge,
};

const Map<String, PathRewriteStrategy> _rewriteStrategies = {
  'ask': PathRewriteStrategy.ask,
  'keep': PathRewriteStrategy.keep,
  'auto': PathRewriteStrategy.auto,
};

const Map<String, BoardConflictChoice> _conflictChoices = {
  'overwrite': BoardConflictChoice.overwrite,
  'rename': BoardConflictChoice.renameIncoming,
  'skip': BoardConflictChoice.skipIncoming,
  'keep': BoardConflictChoice.keepBoth,
};

ImportConflictResolver _resolveImportConflict(BoardConflictChoice choice) =>
    (c) async => choice;

/// Validated import options parsed from the request body.
///
/// The parser preserves the original validation order — mode, then
/// pathRewrite, then onConflict — returning the first error encountered.
class _ImportOptions {
  const _ImportOptions({
    required this.mode,
    required this.rewrite,
    required this.overrides,
    required this.passphrase,
    required this.onConflict,
  }) : error = null;

  const _ImportOptions.error(String message)
      : mode = ImportMode.merge,
        rewrite = PathRewriteStrategy.auto,
        overrides = ImportOverrides.defaults,
        passphrase = null,
        onConflict = BoardConflictChoice.keepBoth,
        error = message;

  final ImportMode mode;
  final PathRewriteStrategy rewrite;
  final ImportOverrides overrides;
  final String? passphrase;
  final BoardConflictChoice onConflict;

  /// Validation error message, or null when every option is valid.
  final String? error;

  factory _ImportOptions.parse(Map<String, dynamic> body) {
    final mode = _importModes[body['mode'] ?? 'merge'];
    if (mode == null) {
      return const _ImportOptions.error('mode must be "merge" or "replace"');
    }
    final rewrite = _rewriteStrategies[body['pathRewrite'] ?? 'auto'];
    if (rewrite == null) {
      return const _ImportOptions.error('pathRewrite must be auto|ask|keep');
    }
    final onConflict = _conflictChoices[body['onConflict'] ?? 'keep'];
    if (onConflict == null) {
      return const _ImportOptions.error(
        'onConflict must be keep|overwrite|rename|skip',
      );
    }

    ImportOverrides overrides = ImportOverrides.defaults;
    final raw = body['overrides'];
    if (raw is Map) {
      overrides = ImportOverrides(
        prefs: raw['prefs'] != false,
        config: raw['config'] != false,
        data: raw['data'] != false,
        workspaces: raw['workspaces'] != false,
      );
    }

    return _ImportOptions(
      mode: mode,
      rewrite: rewrite,
      overrides: overrides,
      passphrase: body['passphrase'] as String?,
      onConflict: onConflict,
    );
  }
}

Future<shelf.Response> _importSettings(_SettingsContext ctx) async {
  final json = ctx.json;
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
  } catch (e) {
    return json(errorJson('Invalid JSON: $e'));
  }

  final src = (body['path'] as String?)?.trim();
  if (src == null || src.isEmpty) {
    return json(errorJson('Provide "path" to the archive'));
  }
  if (!File(src).existsSync()) {
    return json(errorJson('Archive not found: ${p.normalize(src)}'));
  }

  final options = _ImportOptions.parse(body);
  if (options.error != null) {
    return json(errorJson(options.error!));
  }

  try {
    final svc = UserDataArchive();
    final report = await svc.restore(
      archivePath: src,
      mode: options.mode,
      pathRewrite: options.rewrite,
      passphrase: options.passphrase,
      dryRun: body['dryRun'] != false,
      overrides: options.overrides,
      onConflict: _resolveImportConflict(options.onConflict),
    );
    return json(okJson({'report': report.toJson()}));
  } on FormatException catch (e) {
    return json(errorJson(e.message));
  } catch (e) {
    return json(errorJson('Import failed: $e'));
  }
}
