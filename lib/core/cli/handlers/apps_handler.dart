import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

Future<shelf.Response> handleApps(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  final registry = WidgetRegistryService.instance;
  final appRegistry = WidgetAppRegistry.instance;

  // GET /api/apps — list all installed widgets + which are currently active
  if (sub.isEmpty && method == 'GET') {
    final widgets = await registry.loadAll();
    final activeIds = appRegistry.activeIds();
    return json({
      'apps':
          widgets
              .map((m) => {...m.toJson(), 'active': activeIds.contains(m.id)})
              .toList(),
      'activeIds': activeIds,
    });
  }

  // GET /api/apps/dev-skill — return the app development skill doc
  if (sub.length == 1 && sub[0] == 'dev-skill' && method == 'GET') {
    try {
      final content = await rootBundle.loadString(
        'docs/app-development-skill.md',
      );
      return shelf.Response.ok(
        content,
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    } catch (e) {
      return error('Skill doc not found: $e');
    }
  }

  // GET /api/apps/demo — list installed demo apps with their file paths
  if (sub.length == 1 && sub[0] == 'demo' && method == 'GET') {
    final appsDir = Directory(
      '${Platform.environment['HOME']}/.config/yoloit/apps',
    );
    if (!await appsDir.exists()) {
      return json({'demos': <Map<String, Object?>>[]});
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
          'id':
              manifest['id'] ?? entry.path.split(Platform.pathSeparator).last,
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
    return json({'demos': demos});
  }

  // GET /api/apps/demo/:id — show manifest + widget.js content of a demo app
  if (sub.length == 2 && sub[0] == 'demo' && method == 'GET') {
    final id = sub[1];
    final appsDir = '${Platform.environment['HOME']}/.config/yoloit/apps';
    final appDir = Directory('$appsDir/$id');
    if (!await appDir.exists()) {
      return error(
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
    return json({
      'id': id,
      'path': appDir.path,
      'manifest': manifest,
      'manifestRaw': manifestContent,
      'widgetJs': widgetContent,
    });
  }

  // POST /api/apps/install-zip { zipPath: "..." }
  if (sub.length == 1 && sub[0] == 'install-zip' && method == 'POST') {
    final requestBody = await body(request);
    final zipPath = requestBody['zipPath'] as String?;
    if (zipPath == null || zipPath.trim().isEmpty) {
      return error(missingField('zipPath'));
    }
    final zipFile = File(zipPath.trim());
    if (!await zipFile.exists()) {
      return error('ZIP file not found: $zipPath');
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
        return error('Failed to extract ZIP: ${unzipResult.stderr}');
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
      final manifest = await registry.find(appName);
      await registry.loadAll(); // refresh registry cache
      return json(
        okJson({'appName': appName, 'widget': manifest?.toJson()}),
      );
    } catch (e) {
      return error('ZIP install failed: $e');
    }
  }

  // /api/apps/:id/...
  if (sub.length >= 2) {
    final id = sub[0];
    final action = sub[1];

    // GET /api/apps/:id/snapshot — return current UI tree JSON
    if (action == 'snapshot' && method == 'GET') {
      final tree = appRegistry.tree(id);
      if (tree == null) {
        return json(
          errorJson(
            'No render tree available for widget "$id". Is it running?',
          ),
        );
      }
      return json(okJson({'widgetId': id, 'tree': tree}));
    }

    // POST /api/apps/:id/execute — call JS event
    if (action == 'execute' && method == 'POST') {
      final requestBody = await body(request);
      final actionId = requestBody['action'] as String?;
      if (actionId == null || actionId.isEmpty) {
        return error(missingField('action'));
      }
      final engine = appRegistry.engine(id);
      if (engine == null) {
        return json(
          errorJson('Widget "$id" is not currently running'),
        );
      }
      final payload = requestBody['payload'] as Map<String, dynamic>?;
      engine.callEvent(actionId, payload);
      return json(okJson({'widgetId': id, 'action': actionId}));
    }

    // GET /api/apps/:id/logs — return console.log buffer
    if (action == 'logs' && method == 'GET') {
      final engine = appRegistry.engine(id);
      if (engine == null) {
        return json(
          errorJson(
            'App "$id" is not currently running',
            extra: {'logs': <Map<String, dynamic>>[]},
          ),
        );
      }
      final logs = engine.peekLogs();
      return json(okJson({'widgetId': id, 'logs': logs}));
    }

    // POST /api/apps/:id/reload — hot-reload widget JS without restarting the app
    if (action == 'reload' && method == 'POST') {
      final ok = await appRegistry.triggerReload(id);
      if (!ok) {
        return json(
          errorJson('Widget "$id" is not currently running'),
        );
      }
      return json(
        okJson({'widgetId': id, 'message': 'Widget reloaded'}),
      );
    }

    // POST /api/apps/:id/screenshot
    if (action == 'screenshot' && method == 'POST') {
      // TODO: implement full screenshot once BoardScreenshotService.capturePanel(panelId) is wired to widgetId lookup
      return json(
        errorJson(
          'Widget screenshot requires the panel to be visible on screen. Use app:snapshot for the render tree.',
        ),
      );
    }
  }

  return notFound(unknownRoute('app'));
}
