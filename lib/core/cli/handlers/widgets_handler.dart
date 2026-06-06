import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

Future<shelf.Response> handleWidgets(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  final registry = WidgetRegistryService.instance;

  // GET /api/widgets — list all installed widgets
  if (sub.isEmpty && method == 'GET') {
    final widgets = await registry.loadAll();
    return json({'widgets': widgets.map((m) => m.toJson()).toList()});
  }

  // POST /api/widgets/install  { path: "..." }
  if (sub.length == 1 && sub[0] == 'install' && method == 'POST') {
    final requestBody = await body(request);
    final srcPath = requestBody['path'] as String?;
    if (srcPath == null || srcPath.trim().isEmpty) {
      return error('Missing "path" field');
    }
    final manifest = await registry.install(srcPath.trim());
    if (manifest == null) {
      return error('Failed to install widget from: $srcPath');
    }
    return json({'ok': true, 'widget': manifest.toJson()});
  }

  // DELETE /api/widgets/:id
  if (sub.length == 1 && method == 'DELETE') {
    final id = sub[0];
    final removed = await registry.remove(id);
    return json({'ok': removed, 'id': id});
  }

  // GET /api/widgets/:id — single widget details
  if (sub.length == 1 && method == 'GET') {
    final manifest = await registry.find(sub[0]);
    if (manifest == null) return notFound('Widget not found: ${sub[0]}');
    return json({'widget': manifest.toJson()});
  }

  return notFound('Unknown widget route');
}
