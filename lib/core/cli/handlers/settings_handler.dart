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

  ImportMode mode;
  switch (body['mode']) {
    case 'replace':
      mode = ImportMode.replace;
    case 'merge':
    case null:
      mode = ImportMode.merge;
    default:
      return json(errorJson('mode must be "merge" or "replace"'));
  }

  PathRewriteStrategy rewrite;
  switch (body['pathRewrite']) {
    case 'ask':
      rewrite = PathRewriteStrategy.ask;
    case 'keep':
      rewrite = PathRewriteStrategy.keep;
    case 'auto':
    case null:
      rewrite = PathRewriteStrategy.auto;
    default:
      return json(errorJson('pathRewrite must be auto|ask|keep'));
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

  final passphrase = body['passphrase'] as String?;

  BoardConflictChoice? onConflict;
  switch (body['onConflict']) {
    case 'overwrite':
      onConflict = BoardConflictChoice.overwrite;
    case 'rename':
      onConflict = BoardConflictChoice.renameIncoming;
    case 'skip':
      onConflict = BoardConflictChoice.skipIncoming;
    case 'keep':
    case null:
      onConflict = BoardConflictChoice.keepBoth;
    default:
      return json(errorJson('onConflict must be keep|overwrite|rename|skip'));
  }

  try {
    final svc = UserDataArchive();
    final report = await svc.restore(
      archivePath: src,
      mode: mode,
      pathRewrite: rewrite,
      passphrase: passphrase,
      dryRun: body['dryRun'] != false,
      overrides: overrides,
      onConflict: (c) async => onConflict!,
    );
    return json(okJson({'report': report.toJson()}));
  } on FormatException catch (e) {
    return json(errorJson(e.message));
  } catch (e) {
    return json(errorJson('Import failed: $e'));
  }
}
