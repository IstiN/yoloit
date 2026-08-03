import 'dart:async';
import 'dart:ui';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/handler_helpers.dart';
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Immutable bundle of everything a `/groups` route handler needs: the
/// target board/cubit, the request, and the injected response callbacks.
class _GroupRouteContext {
  const _GroupRouteContext({
    required this.board,
    required this.cubit,
    required this.request,
    required this.deps,
  });

  final BoardDocument board;
  final BoardCubit cubit;
  final shelf.Request request;
  final BoardRouteDependencies deps;
}

typedef _GroupCollectionHandler =
    Future<shelf.Response> Function(_GroupRouteContext ctx);

typedef _GroupItemHandler =
    Future<shelf.Response> Function(
      _GroupRouteContext ctx,
      String groupId,
      BoardPanelGroup group,
    );

/// Route table for the `/groups` collection root.
final Map<String, _GroupCollectionHandler> _groupCollectionRoutes = {
  'GET': _listGroups,
  'POST': _createGroup,
};

/// Route table for `/groups/:groupId/...` — `''` is the group root, other
/// keys are the single sub-path segment. (key, method) pairs are mutually
/// exclusive, so table lookup is equivalent to the original route list.
final Map<String, Map<String, _GroupItemHandler>> _groupItemRoutes = {
  '': {'DELETE': _deleteGroup, 'PUT': _updateGroup},
  'panels': {'POST': _addPanelsToGroup, 'DELETE': _removePanelsFromGroup},
  'move': {'POST': _moveGroup},
  'cycle-focus': {'POST': _cycleGroupFocus},
};

/// Handles `/api/boards/:id/groups/...` routes.
Future<shelf.Response> handleGroup(
  String method,
  List<String> sub,
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  BoardRouteDependencies deps,
) async {
  final ctx = _GroupRouteContext(
    board: board,
    cubit: cubit,
    request: request,
    deps: deps,
  );

  // /api/boards/:id/groups collection routes
  if (sub.isEmpty) {
    final handler = _groupCollectionRoutes[method];
    if (handler != null) return handler(ctx);
    return deps.notFound(unknownRoute('group'));
  }

  // /api/boards/:id/groups/:groupId/...
  final groupId = sub[0];
  final group = _findGroup(board, groupId);
  if (group == null) {
    return deps.notFound('Group not found: $groupId');
  }
  if (sub.length > 2) {
    return deps.notFound(unknownRoute('group'));
  }
  final key = sub.length == 1 ? '' : sub[1];
  final handler = _groupItemRoutes[key]?[method];
  if (handler != null) return handler(ctx, groupId, group);
  return deps.notFound(unknownRoute('group'));
}

BoardPanelGroup? _findGroup(BoardDocument board, String groupId) {
  for (final candidate in board.groups) {
    if (candidate.id == groupId) {
      return candidate;
    }
  }
  return null;
}

// GET /api/boards/:id/groups → list groups
Future<shelf.Response> _listGroups(_GroupRouteContext ctx) async {
  return ctx.deps.json({
    'ok': true,
    'groups': ctx.board.groups.map((group) => group.toJson()).toList(),
  });
}

// POST /api/boards/:id/groups → create group
Future<shelf.Response> _createGroup(_GroupRouteContext ctx) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final name = requestBody['name'] as String?;
  if (name == null || name.trim().isEmpty) {
    return ctx.deps.error(missingField('name'));
  }
  final panelIds = _parsePanelIds(requestBody['panels']);
  final colorValue = _parseColor(requestBody['color']);
  await ctx.cubit.createGroup(
    ctx.board.id,
    name: name,
    panelIds: panelIds,
    color: colorValue,
  );
  ctx.deps.scheduleRebuild();
  BoardDocument? updatedBoard;
  for (final candidate in ctx.cubit.state.boards) {
    if (candidate.id == ctx.board.id) {
      updatedBoard = candidate;
      break;
    }
  }
  BoardPanelGroup? created;
  final groups = updatedBoard?.groups;
  if (groups != null && groups.isNotEmpty) created = groups.last;
  return ctx.deps.json({
    'ok': true,
    'message': 'Group "$name" created',
    'group': created?.toJson(),
  });
}

// DELETE /api/boards/:id/groups/:groupId
Future<shelf.Response> _deleteGroup(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  await ctx.cubit.deleteGroup(ctx.board.id, groupId);
  ctx.deps.scheduleRebuild();
  return ctx.deps.json(okJson({'message': 'Group deleted'}));
}

// PUT /api/boards/:id/groups/:groupId → rename, color, collapse
Future<shelf.Response> _updateGroup(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final newName = requestBody['name'] as String?;
  final colorRaw = requestBody['color'];
  final collapsed = requestBody['collapsed'] as bool?;
  if (newName != null) {
    await ctx.cubit.renameGroup(ctx.board.id, groupId, newName);
  }
  if (colorRaw != null) {
    await ctx.cubit.setGroupColor(ctx.board.id, groupId, _parseColor(colorRaw));
  }
  if (collapsed != null && collapsed != group.collapsed) {
    await ctx.cubit.toggleGroupCollapse(ctx.board.id, groupId);
  }
  ctx.deps.scheduleRebuild();
  BoardDocument? updatedBoard;
  for (final candidate in ctx.cubit.state.boards) {
    if (candidate.id == ctx.board.id) {
      updatedBoard = candidate;
      break;
    }
  }
  BoardPanelGroup? updated;
  if (updatedBoard != null) {
    for (final candidate in updatedBoard.groups) {
      if (candidate.id == groupId) {
        updated = candidate;
        break;
      }
    }
  }
  return ctx.deps.json(okJson({'group': updated?.toJson()}));
}

// POST /api/boards/:id/groups/:groupId/panels → add panels
Future<shelf.Response> _addPanelsToGroup(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final panelIds = _parsePanelIds(requestBody['panels']);
  if (panelIds.isEmpty) return ctx.deps.error(missingField('panels'));
  await ctx.cubit.addPanelsToGroup(ctx.board.id, groupId, panelIds);
  ctx.deps.scheduleRebuild();
  return ctx.deps.json(okJson({'message': 'Panels added to group'}));
}

// DELETE /api/boards/:id/groups/:groupId/panels → remove panels
Future<shelf.Response> _removePanelsFromGroup(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final panelIds = _parsePanelIds(requestBody['panels']);
  if (panelIds.isEmpty) return ctx.deps.error(missingField('panels'));
  await ctx.cubit.removePanelsFromGroup(ctx.board.id, groupId, panelIds);
  ctx.deps.scheduleRebuild();
  return ctx.deps.json(okJson({'message': 'Panels removed from group'}));
}

// POST /api/boards/:id/groups/:groupId/move → move group by delta
Future<shelf.Response> _moveGroup(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final dx = (requestBody['dx'] as num?)?.toDouble() ?? 0.0;
  final dy = (requestBody['dy'] as num?)?.toDouble() ?? 0.0;
  await ctx.cubit.moveGroup(ctx.board.id, groupId, Offset(dx, dy));
  ctx.deps.scheduleRebuild();
  return ctx.deps.json(okJson({'message': 'Group moved'}));
}

// POST /api/boards/:id/groups/:groupId/cycle-focus → cycle collapsed focus
Future<shelf.Response> _cycleGroupFocus(
  _GroupRouteContext ctx,
  String groupId,
  BoardPanelGroup group,
) async {
  final requestBody = await ctx.deps.body(ctx.request);
  final direction = (requestBody['direction'] as num?)?.toInt() ?? 1;
  await ctx.cubit.cycleGroupFocus(ctx.board.id, groupId, direction);
  ctx.deps.scheduleRebuild();
  return ctx.deps.json(okJson({'message': 'Group focus cycled'}));
}

List<String> _parsePanelIds(dynamic value) => parsePanelIds(value);

int? _parseColor(dynamic value) {
  if (value == null || value == 'clear') return null;
  if (value is int) return value;
  if (value is String) {
    final color = parseColor(value);
    return color?.toARGB32();
  }
  return null;
}
