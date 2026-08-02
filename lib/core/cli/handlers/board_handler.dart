import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/group_handler.dart';
import 'package:yoloit/core/cli/handlers/handler_helpers.dart';
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Future<shelf.Response> _defaultGridBoard(
  BoardCubit cubit,
  BoardDocument board,
  Map<String, dynamic> body,
) async {
  return shelf.Response.notFound(
    jsonEncode({'ok': false, 'error': 'Grid route not implemented'}),
    headers: {'content-type': 'application/json'},
  );
}

/// Shared context for board route handlers: the matched request plus every
/// callback `handleBoard` receives, so each route handler takes one parameter.
class _BoardRouteContext {
  _BoardRouteContext({
    required this.method,
    required this.sub,
    required this.board,
    required this.cubit,
    required this.request,
    required this.body,
    required this.json,
    required this.error,
    required this.notFound,
    required this.scheduleRebuild,
    required this.boardDetails,
    required this.updateBoard,
    required this.boardSnapshot,
    required this.applyYaml,
    required this.undoBoard,
    required this.redoBoard,
    required this.boardScreenshot,
    required this.boardSvg,
    required this.listPanels,
    required this.createPanel,
    required this.handlePanel,
    required this.listLinks,
    required this.createLink,
    required this.updateLink,
    required this.listPanelTypes,
    required this.updateViewport,
    required this.fitViewport,
    required this.arrangeBoard,
    required this.gridBoard,
  });

  final String method;
  final List<String> sub;
  final BoardDocument board;
  final BoardCubit cubit;
  final shelf.Request request;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final shelf.Response Function(String) error;
  final shelf.Response Function(String) notFound;
  final void Function() scheduleRebuild;
  final shelf.Response Function(BoardDocument) boardDetails;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  updateBoard;
  final shelf.Response Function(BoardDocument, {String format}) boardSnapshot;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    shelf.Request,
  )
  applyYaml;
  final Future<shelf.Response> Function(BoardCubit, BoardDocument) undoBoard;
  final Future<shelf.Response> Function(BoardCubit, BoardDocument) redoBoard;
  final Future<shelf.Response> Function(
    BoardDocument, {
    BoardCubit? cubit,
    bool forceOffscreen,
  })
  boardScreenshot;
  final shelf.Response Function(BoardDocument) boardSvg;
  final shelf.Response Function(BoardDocument) listPanels;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  createPanel;
  final Future<shelf.Response> Function(
    String,
    List<String>,
    BoardDocument,
    BoardPanelInstance,
    BoardCubit,
    shelf.Request,
  )
  handlePanel;
  final shelf.Response Function(BoardDocument) listLinks;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  createLink;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    String,
    Map<String, dynamic>,
  )
  updateLink;
  final shelf.Response Function() listPanelTypes;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  updateViewport;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  fitViewport;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  arrangeBoard;
  final Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    Map<String, dynamic>,
  )
  gridBoard;
}

/// A board route: either a literal `method` + `segments` match, or a custom
/// `matches` predicate for dynamic segments (e.g. `panels/:panelId/...`).
typedef _BoardRoute = ({
  String? method,
  List<String>? segments,
  bool Function(String method, List<String> sub)? matches,
  Future<shelf.Response> Function(_BoardRouteContext ctx) handler,
});

bool _routeMatches(_BoardRoute route, String method, List<String> sub) {
  final predicate = route.matches;
  if (predicate != null) return predicate(method, sub);
  if (route.method != method) return false;
  final segments = route.segments!;
  if (segments.length != sub.length) return false;
  for (var i = 0; i < segments.length; i++) {
    if (segments[i] != sub[i]) return false;
  }
  return true;
}

// GET /api/boards/:id → board details
Future<shelf.Response> _boardDetailsRoute(_BoardRouteContext ctx) {
  return Future.value(ctx.boardDetails(ctx.board));
}

// PUT /api/boards/:id → update board (rename, focus)
Future<shelf.Response> _updateBoardRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.updateBoard(ctx.cubit, ctx.board, requestBody);
}

// DELETE /api/boards/:id → delete board
Future<shelf.Response> _deleteBoardRoute(_BoardRouteContext ctx) async {
  await ctx.cubit.deleteBoard(ctx.board.id);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'message': 'Deleted board ${ctx.board.name}'});
}

// POST /api/boards/:id/archive → archive board
Future<shelf.Response> _archiveBoardRoute(_BoardRouteContext ctx) async {
  await ctx.cubit.archiveBoard(ctx.board.id);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'message': 'Archived board ${ctx.board.name}'});
}

// POST /api/boards/:id/unarchive → unarchive board
Future<shelf.Response> _unarchiveBoardRoute(_BoardRouteContext ctx) async {
  await ctx.cubit.unarchiveBoard(ctx.board.id);
  ctx.scheduleRebuild();
  return ctx.json({
    'ok': true,
    'message': 'Unarchived board ${ctx.board.name}',
  });
}

// GET /api/boards/:id/snapshot
Future<shelf.Response> _boardSnapshotRoute(_BoardRouteContext ctx) {
  final format = ctx.request.url.queryParameters['format'] ?? 'md';
  return Future.value(ctx.boardSnapshot(ctx.board, format: format));
}

// POST /api/boards/:id/apply → apply YAML bulk operations
Future<shelf.Response> _applyYamlRoute(_BoardRouteContext ctx) {
  return ctx.applyYaml(ctx.cubit, ctx.board, ctx.request);
}

// POST /api/boards/:id/undo → undo latest panel history batch
Future<shelf.Response> _undoBoardRoute(_BoardRouteContext ctx) {
  return ctx.undoBoard(ctx.cubit, ctx.board);
}

// POST /api/boards/:id/redo → redo latest undone panel history batch
Future<shelf.Response> _redoBoardRoute(_BoardRouteContext ctx) {
  return ctx.redoBoard(ctx.cubit, ctx.board);
}

// GET /api/boards/:id/screenshot
Future<shelf.Response> _boardScreenshotRoute(_BoardRouteContext ctx) {
  final forceOffscreen = ctx.request.url.queryParameters['mode'] == 'offscreen';
  return ctx.boardScreenshot(
    ctx.board,
    cubit: ctx.cubit,
    forceOffscreen: forceOffscreen,
  );
}

// GET /api/boards/:id/svg
Future<shelf.Response> _boardSvgRoute(_BoardRouteContext ctx) {
  return Future.value(ctx.boardSvg(ctx.board));
}

// GET /api/boards/:id/panels
Future<shelf.Response> _listPanelsRoute(_BoardRouteContext ctx) {
  return Future.value(ctx.listPanels(ctx.board));
}

// POST /api/boards/:id/panels → create panel
Future<shelf.Response> _createPanelRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.createPanel(ctx.cubit, ctx.board, requestBody);
}

// /api/boards/:id/panels/:panelIdOrTitle/...
Future<shelf.Response> _panelSubRoute(_BoardRouteContext ctx) {
  final panel = findPanel(ctx.board, ctx.sub[1]);
  if (panel == null) {
    return Future.value(ctx.notFound('Panel not found: ${ctx.sub[1]}'));
  }
  final panelSub = ctx.sub.sublist(2);
  return ctx.handlePanel(
    ctx.method,
    panelSub,
    ctx.board,
    panel,
    ctx.cubit,
    ctx.request,
  );
}

// GET /api/boards/:id/links
Future<shelf.Response> _listLinksRoute(_BoardRouteContext ctx) {
  return Future.value(ctx.listLinks(ctx.board));
}

// POST /api/boards/:id/links → create link
Future<shelf.Response> _createLinkRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.createLink(ctx.cubit, ctx.board, requestBody);
}

// DELETE /api/boards/:id/links/:linkId
Future<shelf.Response> _deleteLinkRoute(_BoardRouteContext ctx) async {
  await ctx.cubit.removeLink(ctx.sub[1], boardId: ctx.board.id);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'message': 'Link deleted'});
}

// PUT /api/boards/:id/links/:linkId → update link style/color
Future<shelf.Response> _updateLinkRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.updateLink(ctx.cubit, ctx.board, ctx.sub[1], requestBody);
}

// GET /api/boards/:id/panel-types → list available panel types
Future<shelf.Response> _listPanelTypesRoute(_BoardRouteContext ctx) {
  return Future.value(ctx.listPanelTypes());
}

// PUT /api/boards/:id/viewport → set scale/translation
Future<shelf.Response> _updateViewportRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.updateViewport(ctx.cubit, ctx.board, requestBody);
}

// POST /api/boards/:id/fit → auto-fit viewport to show all panels
Future<shelf.Response> _fitViewportRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.fitViewport(ctx.cubit, ctx.board, requestBody);
}

// POST /api/boards/:id/arrange → auto-layout panels in tree/mindmap structure
Future<shelf.Response> _arrangeBoardRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.arrangeBoard(ctx.cubit, ctx.board, requestBody);
}

// POST /api/boards/:id/grid → toggle/adjust grid view
Future<shelf.Response> _gridBoardRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  return ctx.gridBoard(ctx.cubit, ctx.board, requestBody);
}

// GET /api/boards/:id/select → current selection
Future<shelf.Response> _getSelectionRoute(_BoardRouteContext ctx) {
  return Future.value(
    ctx.json({
      'ok': true,
      'selected': ctx.cubit.state.selectedPanelIds.toList(),
    }),
  );
}

// POST /api/boards/:id/copy → copy panels to clipboard
Future<shelf.Response> _copyPanelsRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final panelIds = parsePanelIds(requestBody['panels']);
  final ids = panelIds.isNotEmpty
      ? panelIds.toSet()
      : ctx.cubit.state.selectedPanelIds;
  final copied = await ctx.cubit.copyPanels(ids);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'copied': copied});
}

// POST /api/boards/:id/paste → paste panels from clipboard
Future<shelf.Response> _pastePanelsRoute(_BoardRouteContext ctx) async {
  final pasted = await ctx.cubit.pastePanels();
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'pasted': pasted});
}

// POST /api/boards/:id/duplicate → duplicate panels
Future<shelf.Response> _duplicatePanelsRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final panelIds = parsePanelIds(requestBody['panels']);
  final ids = panelIds.isNotEmpty
      ? panelIds.toSet()
      : ctx.cubit.state.selectedPanelIds;
  final duplicated = await ctx.cubit.duplicatePanels(ids);
  ctx.scheduleRebuild();
  return ctx.json({'ok': true, 'duplicated': duplicated});
}

// POST /api/boards/:id/select → select panels by id list or rect
Future<shelf.Response> _selectPanelsRoute(_BoardRouteContext ctx) async {
  final requestBody = await ctx.body(ctx.request);
  final panelIds = _parsePanelIds(requestBody['panels']);
  if (panelIds.isNotEmpty) {
    ctx.cubit.selectPanels(panelIds.toSet());
    return ctx.json({'ok': true, 'selected': panelIds});
  }
  final rectRaw = requestBody['rect'];
  if (rectRaw is Map<String, dynamic>) {
    final x = (rectRaw['x'] as num?)?.toDouble() ?? 0;
    final y = (rectRaw['y'] as num?)?.toDouble() ?? 0;
    final width = (rectRaw['width'] as num?)?.toDouble() ?? 0;
    final height = (rectRaw['height'] as num?)?.toDouble() ?? 0;
    ctx.cubit.selectPanelsInRect(Rect.fromLTWH(x, y, width, height));
    return ctx.json({
      'ok': true,
      'selected': ctx.cubit.state.selectedPanelIds.toList(),
    });
  }
  return ctx.error(missingField('panels or rect'));
}

// /api/boards/:id/groups/...
Future<shelf.Response> _groupsRoute(_BoardRouteContext ctx) {
  return handleGroup(
    ctx.method,
    ctx.sub.sublist(1),
    ctx.board,
    ctx.cubit,
    ctx.request,
    (
      body: ctx.body,
      json: ctx.json,
      error: ctx.error,
      notFound: ctx.notFound,
      scheduleRebuild: ctx.scheduleRebuild,
    ),
  );
}

/// Board route table. Order matters and mirrors the original if-chain:
/// e.g. literal `panels` GET/POST must match before the dynamic
/// `panels/:panelIdOrTitle/...` predicate.
final List<_BoardRoute> _boardRoutes = [
  (
    method: 'GET',
    segments: <String>[],
    matches: null,
    handler: _boardDetailsRoute,
  ),
  (
    method: 'PUT',
    segments: <String>[],
    matches: null,
    handler: _updateBoardRoute,
  ),
  (
    method: 'DELETE',
    segments: <String>[],
    matches: null,
    handler: _deleteBoardRoute,
  ),
  (
    method: 'POST',
    segments: ['archive'],
    matches: null,
    handler: _archiveBoardRoute,
  ),
  (
    method: 'POST',
    segments: ['unarchive'],
    matches: null,
    handler: _unarchiveBoardRoute,
  ),
  (
    method: 'GET',
    segments: ['snapshot'],
    matches: null,
    handler: _boardSnapshotRoute,
  ),
  (
    method: 'POST',
    segments: ['apply'],
    matches: null,
    handler: _applyYamlRoute,
  ),
  (method: 'POST', segments: ['undo'], matches: null, handler: _undoBoardRoute),
  (method: 'POST', segments: ['redo'], matches: null, handler: _redoBoardRoute),
  (
    method: 'GET',
    segments: ['screenshot'],
    matches: null,
    handler: _boardScreenshotRoute,
  ),
  (method: 'GET', segments: ['svg'], matches: null, handler: _boardSvgRoute),
  (
    method: 'GET',
    segments: ['panels'],
    matches: null,
    handler: _listPanelsRoute,
  ),
  (
    method: 'POST',
    segments: ['panels'],
    matches: null,
    handler: _createPanelRoute,
  ),
  (
    method: null,
    segments: null,
    matches: (method, sub) => sub.length >= 2 && sub[0] == 'panels',
    handler: _panelSubRoute,
  ),
  (method: 'GET', segments: ['links'], matches: null, handler: _listLinksRoute),
  (
    method: 'POST',
    segments: ['links'],
    matches: null,
    handler: _createLinkRoute,
  ),
  (
    method: null,
    segments: null,
    matches: (method, sub) =>
        sub.length == 2 && sub[0] == 'links' && method == 'DELETE',
    handler: _deleteLinkRoute,
  ),
  (
    method: null,
    segments: null,
    matches: (method, sub) =>
        sub.length == 2 && sub[0] == 'links' && method == 'PUT',
    handler: _updateLinkRoute,
  ),
  (
    method: 'GET',
    segments: ['panel-types'],
    matches: null,
    handler: _listPanelTypesRoute,
  ),
  (
    method: 'PUT',
    segments: ['viewport'],
    matches: null,
    handler: _updateViewportRoute,
  ),
  (
    method: 'POST',
    segments: ['fit'],
    matches: null,
    handler: _fitViewportRoute,
  ),
  (
    method: 'POST',
    segments: ['arrange'],
    matches: null,
    handler: _arrangeBoardRoute,
  ),
  (method: 'POST', segments: ['grid'], matches: null, handler: _gridBoardRoute),
  (
    method: 'GET',
    segments: ['select'],
    matches: null,
    handler: _getSelectionRoute,
  ),
  (
    method: 'POST',
    segments: ['copy'],
    matches: null,
    handler: _copyPanelsRoute,
  ),
  (
    method: 'POST',
    segments: ['paste'],
    matches: null,
    handler: _pastePanelsRoute,
  ),
  (
    method: 'POST',
    segments: ['duplicate'],
    matches: null,
    handler: _duplicatePanelsRoute,
  ),
  (
    method: 'POST',
    segments: ['select'],
    matches: null,
    handler: _selectPanelsRoute,
  ),
  (
    method: null,
    segments: null,
    matches: (method, sub) => sub.isNotEmpty && sub[0] == 'groups',
    handler: _groupsRoute,
  ),
];

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
  required shelf.Response Function(BoardDocument, {String format})
  boardSnapshot,
  required Future<shelf.Response> Function(
    BoardCubit,
    BoardDocument,
    shelf.Request,
  )
  applyYaml,
  required Future<shelf.Response> Function(BoardCubit, BoardDocument) undoBoard,
  required Future<shelf.Response> Function(BoardCubit, BoardDocument) redoBoard,
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
  Future<shelf.Response> Function(
        BoardCubit,
        BoardDocument,
        Map<String, dynamic>,
      )
      gridBoard =
      _defaultGridBoard,
}) async {
  final ctx = _BoardRouteContext(
    method: method,
    sub: sub,
    board: board,
    cubit: cubit,
    request: request,
    body: body,
    json: json,
    error: error,
    notFound: notFound,
    scheduleRebuild: scheduleRebuild,
    boardDetails: boardDetails,
    updateBoard: updateBoard,
    boardSnapshot: boardSnapshot,
    applyYaml: applyYaml,
    undoBoard: undoBoard,
    redoBoard: redoBoard,
    boardScreenshot: boardScreenshot,
    boardSvg: boardSvg,
    listPanels: listPanels,
    createPanel: createPanel,
    handlePanel: handlePanel,
    listLinks: listLinks,
    createLink: createLink,
    updateLink: updateLink,
    listPanelTypes: listPanelTypes,
    updateViewport: updateViewport,
    fitViewport: fitViewport,
    arrangeBoard: arrangeBoard,
    gridBoard: gridBoard,
  );
  for (final route in _boardRoutes) {
    if (_routeMatches(route, method, sub)) return route.handler(ctx);
  }
  return notFound('Unknown board route');
}

List<String> _parsePanelIds(dynamic value) => parsePanelIds(value);
