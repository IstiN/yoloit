import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

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
  // GET .../panels/:id → panel details + content
  if (sub.isEmpty && method == 'GET') {
    return panelDetails(panel);
  }
  // PUT .../panels/:id → update panel props
  if (sub.isEmpty && method == 'PUT') {
    final requestBody = await body(request);
    return updatePanel(cubit, board, panel, requestBody);
  }
  // DELETE .../panels/:id
  if (sub.isEmpty && method == 'DELETE') {
    if (panel.type == 'board.widget.custom') {
      WidgetEngineManager.instance.remove(panel.id);
    }
    await cubit.removePanel(panel.id, boardId: board.id);
    scheduleRebuild();
    return json({'ok': true, 'message': 'Panel deleted'});
  }
  // POST .../panels/:id/action  { action: "send", ... }
  if (sub.length == 1 && sub[0] == 'action' && method == 'POST') {
    final requestBody = await body(request);
    return panelAction(cubit, board, panel, requestBody);
  }
  // GET .../panels/:id/screenshot
  if (sub.length == 1 && sub[0] == 'screenshot' && method == 'GET') {
    return _panelScreenshot(board, panel);
  }

  return notFound('Unknown panel route');
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
