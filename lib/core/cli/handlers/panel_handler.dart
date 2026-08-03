import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

/// Immutable bundle of everything a `/panels/:id` route handler needs:
/// the target board/panel plus the injected response/delegate callbacks.
class _PanelRouteContext {
  const _PanelRouteContext({
    required this.board,
    required this.panel,
    required this.cubit,
    required this.request,
    required this.body,
    required this.json,
    required this.scheduleRebuild,
    required this.panelDetails,
    required this.updatePanel,
    required this.panelAction,
  });

  final BoardDocument board;
  final BoardPanelInstance panel;
  final BoardCubit cubit;
  final shelf.Request request;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final void Function() scheduleRebuild;
  final shelf.Response Function(BoardPanelInstance) panelDetails;
  final Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )
  updatePanel;
  final Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )
  panelAction;
}

typedef _PanelRouteHandler =
    Future<shelf.Response> Function(_PanelRouteContext ctx);

/// Route table for `/panels/:id` — `''` is the panel root, other keys are
/// the single sub-path segment. (key, method) pairs are mutually exclusive,
/// so table lookup is equivalent to the original if-chain.
final Map<String, Map<String, _PanelRouteHandler>> _panelRoutes = {
  '': {
    'GET': _handlePanelDetails,
    'PUT': _handleUpdatePanel,
    'DELETE': _handleDeletePanel,
  },
  'action': {'POST': _handlePanelAction},
  'screenshot': {'GET': _handlePanelScreenshot},
};

Future<shelf.Response> handlePanel(
  String method,
  List<String> sub,
  BoardDocument board,
  BoardPanelInstance panel,
  BoardCubit cubit,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  required void Function() scheduleRebuild,
  required shelf.Response Function(BoardPanelInstance) panelDetails,
  required Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )
  updatePanel,
  required Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )
  panelAction,
}) async {
  if (sub.length > 1) {
    return notFound('Unknown panel route');
  }
  final ctx = _PanelRouteContext(
    board: board,
    panel: panel,
    cubit: cubit,
    request: request,
    body: body,
    json: json,
    scheduleRebuild: scheduleRebuild,
    panelDetails: panelDetails,
    updatePanel: updatePanel,
    panelAction: panelAction,
  );
  final key = sub.isEmpty ? '' : sub[0];
  final handler = _panelRoutes[key]?[method];
  if (handler == null) {
    return notFound('Unknown panel route');
  }
  return handler(ctx);
}

// GET .../panels/:id → panel details + content
Future<shelf.Response> _handlePanelDetails(_PanelRouteContext ctx) async {
  return ctx.panelDetails(ctx.panel);
}

// PUT .../panels/:id → update panel props
Future<shelf.Response> _handleUpdatePanel(_PanelRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.updatePanel(ctx.cubit, ctx.board, ctx.panel, requestBody);
}

// DELETE .../panels/:id
Future<shelf.Response> _handleDeletePanel(_PanelRouteContext ctx) async {
  if (ctx.panel.type == 'board.widget.custom') {
    WidgetEngineManager.instance.remove(ctx.panel.id);
  }
  await ctx.cubit.removePanel(ctx.panel.id, boardId: ctx.board.id);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'message': 'Panel deleted'});
}

// POST .../panels/:id/action  { action: "send", ... }
Future<shelf.Response> _handlePanelAction(_PanelRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.panelAction(ctx.cubit, ctx.board, ctx.panel, requestBody);
}

// GET .../panels/:id/screenshot
Future<shelf.Response> _handlePanelScreenshot(_PanelRouteContext ctx) {
  return _panelScreenshot(ctx.board, ctx.panel);
}

Future<shelf.Response> _panelScreenshot(
  BoardDocument board,
  BoardPanelInstance panel,
) async {
  final png = await BoardOffscreenRenderer.instance.renderPanel(board, panel);
  if (png == null) {
    return shelf.Response(
      400,
      body: '{"ok":false,"error":"Failed to capture panel screenshot"}',
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return shelf.Response.ok(png, headers: {'content-type': 'image/png'});
}
