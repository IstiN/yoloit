import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Future<shelf.Response> handleBoard(
  String method,
  List<String> sub,
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  required void Function() scheduleRebuild,
  required shelf.Response Function(BoardDocument) boardDetails,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  updateBoard,
  required shelf.Response Function(BoardDocument, {String format}) boardSnapshot,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    shelf.Request,
  )
  applyYaml,
  required Future<shelf.Response> Function(BoardCubit, BoardDocument) undoBoard,
  required Future<shelf.Response> Function(
    BoardDocument, {
    BoardCubit? cubit,
    bool forceOffscreen,
  })
  boardScreenshot,
  required shelf.Response Function(BoardDocument) boardSvg,
  required shelf.Response Function(BoardDocument) listPanels,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  createPanel,
  required Future<shelf.Response> Function(
    String,
    List<String>,
    BoardDocument,
    BoardPanelInstance,
    BoardCubit,
    shelf.Request,
  )
  handlePanel,
  required shelf.Response Function(BoardDocument) listLinks,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  createLink,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    String,
    Map<String, dynamic>,
  )
  updateLink,
  required shelf.Response Function() listPanelTypes,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  updateViewport,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  fitViewport,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  arrangeBoard,
}) async {
  // GET /api/boards/:id → board details
  if (sub.isEmpty && method == 'GET') {
    return boardDetails(board);
  }
  // PUT /api/boards/:id → update board (rename, focus)
  if (sub.isEmpty && method == 'PUT') {
    final requestBody = await body(request);
    return updateBoard(cubit, board, requestBody);
  }
  // DELETE /api/boards/:id → delete board
  if (sub.isEmpty && method == 'DELETE') {
    await cubit.deleteBoard(board.id);
    scheduleRebuild();
    return json({'ok': true, 'message': 'Deleted board ${board.name}'});
  }
  // GET /api/boards/:id/snapshot
  if (sub.length == 1 && sub[0] == 'snapshot' && method == 'GET') {
    final format = request.url.queryParameters['format'] ?? 'md';
    return boardSnapshot(board, format: format);
  }
  // POST /api/boards/:id/apply → apply YAML bulk operations
  if (sub.length == 1 && sub[0] == 'apply' && method == 'POST') {
    return applyYaml(cubit, board, request);
  }
  // POST /api/boards/:id/undo → undo latest panel history batch
  if (sub.length == 1 && sub[0] == 'undo' && method == 'POST') {
    return undoBoard(cubit, board);
  }
  // GET /api/boards/:id/screenshot
  if (sub.length == 1 && sub[0] == 'screenshot' && method == 'GET') {
    final forceOffscreen = request.url.queryParameters['mode'] == 'offscreen';
    return boardScreenshot(
      board,
      cubit: cubit,
      forceOffscreen: forceOffscreen,
    );
  }
  // GET /api/boards/:id/svg
  if (sub.length == 1 && sub[0] == 'svg' && method == 'GET') {
    return boardSvg(board);
  }
  // GET /api/boards/:id/panels
  if (sub.length == 1 && sub[0] == 'panels' && method == 'GET') {
    return listPanels(board);
  }
  // POST /api/boards/:id/panels → create panel
  if (sub.length == 1 && sub[0] == 'panels' && method == 'POST') {
    final requestBody = await body(request);
    return createPanel(cubit, board, requestBody);
  }
  // /api/boards/:id/panels/:panelIdOrTitle/...
  if (sub.length >= 2 && sub[0] == 'panels') {
    final panel = findPanel(board, sub[1]);
    if (panel == null) return notFound('Panel not found: ${sub[1]}');
    final panelSub = sub.sublist(2);
    return handlePanel(method, panelSub, board, panel, cubit, request);
  }
  // GET /api/boards/:id/links
  if (sub.length == 1 && sub[0] == 'links' && method == 'GET') {
    return listLinks(board);
  }
  // POST /api/boards/:id/links → create link
  if (sub.length == 1 && sub[0] == 'links' && method == 'POST') {
    final requestBody = await body(request);
    return createLink(cubit, board, requestBody);
  }
  // DELETE /api/boards/:id/links/:linkId
  if (sub.length == 2 && sub[0] == 'links' && method == 'DELETE') {
    await cubit.removeLink(sub[1], boardId: board.id);
    scheduleRebuild();
    return json({'ok': true, 'message': 'Link deleted'});
  }
  // PUT /api/boards/:id/links/:linkId → update link style/color
  if (sub.length == 2 && sub[0] == 'links' && method == 'PUT') {
    final requestBody = await body(request);
    return updateLink(cubit, board, sub[1], requestBody);
  }
  // GET /api/boards/:id/panel-types → list available panel types
  if (sub.length == 1 && sub[0] == 'panel-types' && method == 'GET') {
    return listPanelTypes();
  }
  // PUT /api/boards/:id/viewport → set scale/translation
  if (sub.length == 1 && sub[0] == 'viewport' && method == 'PUT') {
    final requestBody = await body(request);
    return updateViewport(cubit, board, requestBody);
  }
  // POST /api/boards/:id/fit → auto-fit viewport to show all panels
  if (sub.length == 1 && sub[0] == 'fit' && method == 'POST') {
    final requestBody = await body(request);
    return fitViewport(cubit, board, requestBody);
  }
  // POST /api/boards/:id/arrange → auto-layout panels in tree/mindmap structure
  if (sub.length == 1 && sub[0] == 'arrange' && method == 'POST') {
    final requestBody = await body(request);
    return arrangeBoard(cubit, board, requestBody);
  }

  return notFound('Unknown board route');
}
