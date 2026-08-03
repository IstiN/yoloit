import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

/// Immutable bundle of everything a `/widgets` route handler needs: the
/// request data, the registry, and the injected response callbacks.
class _WidgetsRouteContext {
  const _WidgetsRouteContext({
    required this.sub,
    required this.request,
    required this.registry,
    required this.body,
    required this.json,
    required this.error,
    required this.notFound,
  });

  final List<String> sub;
  final shelf.Request request;
  final WidgetRegistryService registry;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final shelf.Response Function(String) error;
  final shelf.Response Function(String) notFound;
}

typedef _WidgetsRouteHandler =
    Future<shelf.Response> Function(_WidgetsRouteContext ctx);

/// Route table for fixed `/widgets` paths — `''` is the collection root,
/// other keys are exact single-segment paths.
final Map<String, Map<String, _WidgetsRouteHandler>> _widgetsRoutes = {
  '': {'GET': _handleListWidgets},
  'install': {'POST': _handleInstallWidget},
};

/// Fallback table for `/widgets/:id` — any other single path segment is
/// treated as a widget id.
final Map<String, _WidgetsRouteHandler> _widgetByIdRoutes = {
  'GET': _handleGetWidget,
  'DELETE': _handleRemoveWidget,
};

Future<shelf.Response> handleWidgets(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  if (sub.length > 1) {
    return notFound('Unknown widget route');
  }
  final ctx = _WidgetsRouteContext(
    sub: sub,
    request: request,
    registry: WidgetRegistryService.instance,
    body: body,
    json: json,
    error: error,
    notFound: notFound,
  );
  final key = sub.isEmpty ? '' : sub[0];
  final handler =
      _widgetsRoutes[key]?[method] ??
      (sub.isEmpty ? null : _widgetByIdRoutes[method]);
  if (handler == null) {
    return notFound('Unknown widget route');
  }
  return handler(ctx);
}

// GET /api/widgets — list all installed widgets
Future<shelf.Response> _handleListWidgets(_WidgetsRouteContext ctx) async {
  final widgets = await ctx.registry.loadAll();
  return ctx.json({'widgets': widgets.map((m) => m.toJson()).toList()});
}

// POST /api/widgets/install  { path: "..." }
Future<shelf.Response> _handleInstallWidget(_WidgetsRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final srcPath = requestBody['path'] as String?;
  if (srcPath == null || srcPath.trim().isEmpty) {
    return ctx.error('Missing "path" field');
  }
  final manifest = await ctx.registry.install(srcPath.trim());
  if (manifest == null) {
    return ctx.error('Failed to install widget from: $srcPath');
  }
  return ctx.json({'ok': true, 'widget': manifest.toJson()});
}

// DELETE /api/widgets/:id
Future<shelf.Response> _handleRemoveWidget(_WidgetsRouteContext ctx) async {
  final id = ctx.sub[0];
  final removed = await ctx.registry.remove(id);
  return ctx.json({'ok': removed, 'id': id});
}

// GET /api/widgets/:id — single widget details
Future<shelf.Response> _handleGetWidget(_WidgetsRouteContext ctx) async {
  final manifest = await ctx.registry.find(ctx.sub[0]);
  if (manifest == null) return ctx.notFound('Widget not found: ${ctx.sub[0]}');
  return ctx.json({'widget': manifest.toJson()});
}
