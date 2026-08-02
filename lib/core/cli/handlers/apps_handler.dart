import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart' show WidgetManifest;
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

typedef _AppsRouteHandler =
    Future<shelf.Response> Function(_AppsRequestContext ctx);

typedef _AppActionHandler =
    Future<shelf.Response> Function(_AppActionContext ctx);

/// Shared request context passed to every extracted route handler.
class _AppsRequestContext {
  const _AppsRequestContext({
    required this.method,
    required this.sub,
    required this.request,
    required this.body,
    required this.json,
    required this.error,
    required this.registry,
    required this.appReg,
  });

  final String method;
  final List<String> sub;
  final shelf.Request request;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final shelf.Response Function(String) error;
  final WidgetRegistryService registry;
  final WidgetAppRegistry appReg;
}

/// A single route entry: HTTP method + exact path segments (`*` matches any
/// single segment).
class _AppsRoute {
  const _AppsRoute(this.method, this.segments, this.handler);

  final String method;
  final List<String> segments;
  final _AppsRouteHandler handler;

  bool matches(String method, List<String> sub) {
    if (method != this.method || sub.length != segments.length) return false;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != '*' && segments[i] != sub[i]) return false;
    }
    return true;
  }
}

/// Context for `/api/apps/:id/:action` routes, with the widget id already
/// resolved against the registry.
class _AppActionContext {
  const _AppActionContext({
    required this.base,
    required this.rawId,
    required this.manifest,
    required this.resolvedId,
  });

  final _AppsRequestContext base;
  final String rawId;
  final WidgetManifest? manifest;
  final String resolvedId;

  shelf.Request get request => base.request;
  Future<Map<String, dynamic>> Function(shelf.Request) get body => base.body;
  shelf.Response Function(Object) get json => base.json;
  shelf.Response Function(String) get error => base.error;
  WidgetAppRegistry get appReg => base.appReg;
}

/// Static route table; order matches the original if-chain (first match wins).
const _appsRoutes = <_AppsRoute>[
  _AppsRoute('GET', <String>[], _listApps),
  _AppsRoute('GET', <String>['dev-skill'], _devSkill),
  _AppsRoute('GET', <String>['demo'], _listDemos),
  _AppsRoute('GET', <String>['demo', '*'], _showDemo),
  _AppsRoute('POST', <String>['install-zip'], _installZip),
];

/// Handlers for `/api/apps/:id/:action`, keyed by `'$method $action'`.
/// Keys are unique, so map lookup is equivalent to the original if-chain.
const _appActionHandlers = <String, _AppActionHandler>{
  'GET help': _appHelp,
  'GET state': _appState,
  'GET snapshot': _appSnapshot,
  'POST execute': _appExecute,
  'GET logs': _appLogs,
  'POST reload': _appReload,
  'POST screenshot': _appScreenshot,
};

Future<shelf.Response> handleApps(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  WidgetRegistryService? registryService,
  WidgetAppRegistry? appRegistry,
}) async {
  final ctx = _AppsRequestContext(
    method: method,
    sub: sub,
    request: request,
    body: body,
    json: json,
    error: error,
    registry: registryService ?? WidgetRegistryService.instance,
    appReg: appRegistry ?? WidgetAppRegistry.instance,
  );

  for (final route in _appsRoutes) {
    if (route.matches(method, sub)) return route.handler(ctx);
  }

  // /api/apps/:id/...
  if (sub.length >= 2) {
    final response = await _handleAppAction(ctx);
    if (response != null) return response;
  }

  return notFound(unknownRoute('app'));
}

// GET /api/apps — list all installed widgets + which are currently active
Future<shelf.Response> _listApps(_AppsRequestContext ctx) async {
  final widgets = await ctx.registry.loadAll();
  final activeIds = ctx.appReg.activeIds();
  return ctx.json({
    'apps':
        widgets
            .map((m) => {...m.toJson(), 'active': activeIds.contains(m.id)})
            .toList(),
    'activeIds': activeIds,
  });
}

// GET /api/apps/dev-skill — return the app development skill doc
Future<shelf.Response> _devSkill(_AppsRequestContext ctx) async {
  try {
    final content = await rootBundle.loadString(
      'docs/app-development-skill.md',
    );
    return shelf.Response.ok(
      content,
      headers: {'content-type': 'text/plain; charset=utf-8'},
    );
  } catch (e) {
    return ctx.error('Skill doc not found: $e');
  }
}

// GET /api/apps/demo — list installed demo apps with their file paths
Future<shelf.Response> _listDemos(_AppsRequestContext ctx) async {
  final appsDir = Directory(
    '${Platform.environment['HOME']}/.config/yoloit/apps',
  );
  if (!await appsDir.exists()) {
    return ctx.json({'demos': <Map<String, Object?>>[]});
  }
  final demos = <Map<String, Object?>>[];
  await for (final entry in appsDir.list()) {
    if (entry is! Directory) continue;
    final manifestFile = File('${entry.path}/manifest.json');
    if (!await manifestFile.exists()) continue;
    try {
      final raw = await manifestFile.readAsString();
      final manifest = jsonDecode(raw) as Map<String, dynamic>;
      demos.add({
        'id': manifest['id'] ?? entry.path.split(Platform.pathSeparator).last,
        'name': manifest['name'] ?? '',
        'description': manifest['description'] ?? '',
        'icon': manifest['icon'] ?? '',
        'network': manifest['network'] ?? false,
        'path': entry.path,
        'files': {
          'manifest': '${entry.path}/manifest.json',
          'widget': '${entry.path}/widget.js',
        },
      });
    } catch (_) {}
  }
  demos.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return ctx.json({'demos': demos});
}

// GET /api/apps/demo/:id — show manifest + widget.js content of a demo app
Future<shelf.Response> _showDemo(_AppsRequestContext ctx) async {
  final id = ctx.sub[1];
  final appsDir = '${Platform.environment['HOME']}/.config/yoloit/apps';
  final appDir = Directory('$appsDir/$id');
  if (!await appDir.exists()) {
    return ctx.error(
      'Demo app "$id" not found. Run app:demo to list available apps.',
    );
  }
  final manifestFile = File('${appDir.path}/manifest.json');
  final widgetFile = File('${appDir.path}/widget.js');
  final manifestContent =
      await manifestFile.exists() ? await manifestFile.readAsString() : null;
  final widgetContent =
      await widgetFile.exists() ? await widgetFile.readAsString() : null;
  Map<String, dynamic> manifest = {};
  try {
    if (manifestContent != null) {
      manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
    }
  } catch (_) {}
  return ctx.json({
    'id': id,
    'path': appDir.path,
    'manifest': manifest,
    'manifestRaw': manifestContent,
    'widgetJs': widgetContent,
  });
}

// POST /api/apps/install-zip { zipPath: "..." }
Future<shelf.Response> _installZip(_AppsRequestContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final zipPath = requestBody['zipPath'] as String?;
  if (zipPath == null || zipPath.trim().isEmpty) {
    return ctx.error(missingField('zipPath'));
  }
  final zipFile = File(zipPath.trim());
  if (!await zipFile.exists()) {
    return ctx.error('ZIP file not found: $zipPath');
  }
  try {
    final zipName = zipFile.path.split(Platform.pathSeparator).last;
    final appNameFromZip =
        zipName.endsWith('.zip')
            ? zipName.substring(0, zipName.length - 4)
            : zipName;
    final appsDir = Directory(
      '${Platform.environment['HOME']}/.config/yoloit/apps',
    );
    await appsDir.create(recursive: true);
    final extractDir = Directory(
      '${appsDir.path}${Platform.pathSeparator}__zip_extract_${DateTime.now().millisecondsSinceEpoch}',
    );
    await extractDir.create();
    final unzipResult = await Process.run('unzip', [
      '-q',
      zipFile.path,
      '-d',
      extractDir.path,
    ]);
    if (unzipResult.exitCode != 0) {
      await extractDir.delete(recursive: true);
      return ctx.error('Failed to extract ZIP: ${unzipResult.stderr}');
    }
    // Find the directory containing widget.js or manifest.json
    Directory? appSource;
    await for (final entity in extractDir.list(recursive: true)) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name == 'widget.js' || name == 'manifest.json') {
          appSource = entity.parent;
          break;
        }
      }
    }
    appSource ??= extractDir;
    // Determine app name from manifest or zip filename
    String appName = appNameFromZip;
    final manifestFile = File(
      '${appSource.path}${Platform.pathSeparator}manifest.json',
    );
    if (await manifestFile.exists()) {
      try {
        final raw =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        appName = (raw['id'] as String?)?.trim() ?? appNameFromZip;
      } catch (_) {}
    }
    final destDir = Directory(
      '${appsDir.path}${Platform.pathSeparator}$appName',
    );
    if (await destDir.exists()) await destDir.delete(recursive: true);
    await Process.run('cp', ['-r', appSource.path, destDir.path]);
    await extractDir.delete(recursive: true);
    final manifest = await ctx.registry.find(appName);
    await ctx.registry.loadAll(); // refresh registry cache
    return ctx.json(
      okJson({'appName': appName, 'widget': manifest?.toJson()}),
    );
  } catch (e) {
    return ctx.error('ZIP install failed: $e');
  }
}

// /api/apps/:id/:action — resolves the widget, then dispatches on
// '$method $action'. Returns null when no action matches (falls through
// to the unknown-route response, as in the original if-chain).
Future<shelf.Response?> _handleAppAction(_AppsRequestContext ctx) async {
  final rawId = ctx.sub[0];
  final action = ctx.sub[1];
  final lookupId = ctx.appReg.resolveLookupKey(rawId);
  final manifest = await ctx.registry.find(rawId);
  final resolvedId = manifest?.id ?? lookupId;

  final handler = _appActionHandlers['${ctx.method} $action'];
  if (handler == null) return null;
  return handler(
    _AppActionContext(
      base: ctx,
      rawId: rawId,
      manifest: manifest,
      resolvedId: resolvedId,
    ),
  );
}

// GET /api/apps/:id/help — CLI help for this app
Future<shelf.Response> _appHelp(_AppActionContext ctx) async {
  final manifest = ctx.manifest;
  if (manifest == null) {
    return ctx.json(
      errorJson(
        'App "${ctx.rawId}" not found. Run app:list to see installed apps.',
      ),
    );
  }
  final running = ctx.appReg.engine(ctx.resolvedId) != null;
  return ctx.json(
    okJson(AppCliUtils.buildHelp(manifest: manifest, running: running)),
  );
}

// GET /api/apps/:id/state — structured export + visible text
Future<shelf.Response> _appState(_AppActionContext ctx) async {
  final engine = ctx.appReg.engine(ctx.resolvedId);
  final tree = ctx.appReg.tree(ctx.resolvedId);
  if (engine == null && tree == null) {
    return ctx.json(
      errorJson(
        'App "${ctx.resolvedId}" is not running. Start with: yoloit app:run ${ctx.resolvedId}',
      ),
    );
  }
  final exported = engine?.exportedState;
  final text = tree == null ? <String>[] : AppCliUtils.extractTextLines(tree);
  return ctx.json(
    okJson({
      'widgetId': ctx.resolvedId,
      'running': engine != null,
      if (exported != null) 'state': exported,
      'text': text,
      if (ctx.manifest != null)
        'help': AppCliUtils.buildHelp(manifest: ctx.manifest!, running: true),
    }),
  );
}

// GET /api/apps/:id/snapshot — return current UI tree JSON
Future<shelf.Response> _appSnapshot(_AppActionContext ctx) async {
  final tree = ctx.appReg.tree(ctx.resolvedId);
  if (tree == null) {
    return ctx.json(
      errorJson(
        'No render tree available for app "${ctx.resolvedId}". '
        'Run: yoloit app:run ${ctx.resolvedId}',
      ),
    );
  }
  return ctx.json(
    okJson({
      'widgetId': ctx.resolvedId,
      'tree': tree,
      'text': AppCliUtils.extractTextLines(tree),
    }),
  );
}

// POST /api/apps/:id/execute — call JS event
Future<shelf.Response> _appExecute(_AppActionContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final actionId = requestBody['action'] as String?;
  if (actionId == null || actionId.isEmpty) {
    return ctx.error(missingField('action'));
  }
  final engine = ctx.appReg.engine(ctx.resolvedId);
  if (engine == null) {
    return ctx.json(
      errorJson(
        'App "${ctx.resolvedId}" is not running. Run: yoloit app:run ${ctx.resolvedId}',
      ),
    );
  }
  final payload = requestBody['payload'] as Map<String, dynamic>?;
  await engine.callEvent(actionId, payload);
  final exported = engine.exportedState;
  return ctx.json(
    okJson({
      'widgetId': ctx.resolvedId,
      'action': actionId,
      if (exported != null) 'state': exported,
    }),
  );
}

// GET /api/apps/:id/logs — return console.log buffer
Future<shelf.Response> _appLogs(_AppActionContext ctx) async {
  final engine = ctx.appReg.engine(ctx.resolvedId);
  if (engine == null) {
    return ctx.json(
      errorJson(
        'App "${ctx.resolvedId}" is not running',
        extra: {'logs': <Map<String, dynamic>>[]},
      ),
    );
  }
  final logs = engine.peekLogs();
  return ctx.json(okJson({'widgetId': ctx.resolvedId, 'logs': logs}));
}

// POST /api/apps/:id/reload — hot-reload widget JS without restarting the app
Future<shelf.Response> _appReload(_AppActionContext ctx) async {
  final ok = await ctx.appReg.triggerReload(ctx.resolvedId);
  if (!ok) {
    return ctx.json(
      errorJson('App "${ctx.resolvedId}" is not currently running'),
    );
  }
  return ctx.json(
    okJson({'widgetId': ctx.resolvedId, 'message': 'Widget reloaded'}),
  );
}

// POST /api/apps/:id/screenshot
Future<shelf.Response> _appScreenshot(_AppActionContext ctx) async {
  // TODO: implement full screenshot once BoardScreenshotService.capturePanel(panelId) is wired to widgetId lookup
  return ctx.json(
    errorJson(
      'Widget screenshot requires the panel to be visible on screen. '
      'Use app:snapshot for the JSON render tree instead.',
    ),
  );
}
