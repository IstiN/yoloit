import 'dart:async';
import 'dart:ui';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/handler_helpers.dart';
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Handles `/api/boards/:id/groups/...` routes.
Future<shelf.Response> handleGroup(
  String method,
  List<String> sub,
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  BoardRouteDependencies deps,
) async {
  final body = deps.body;
  final json = deps.json;
  final error = deps.error;
  final notFound = deps.notFound;
  final scheduleRebuild = deps.scheduleRebuild;

  // /api/boards/:id/groups collection routes
  if (sub.isEmpty) {
    if (method == 'GET') return _listGroups(board, json);
    if (method == 'POST') {
      return _createGroup(board, cubit, request, body, json, error, scheduleRebuild);
    }
    return notFound(unknownRoute('group'));
  }

  // /api/boards/:id/groups/:groupId/...
  final groupId = sub[0];
  final group = _findGroup(board, groupId);
  if (group == null) {
    return notFound('Group not found: $groupId');
  }

  final routes = <(bool Function(), Future<shelf.Response> Function())>[
    (
      () => sub.length == 1 && method == 'DELETE',
      () => _deleteGroup(board, cubit, groupId, json, scheduleRebuild),
    ),
    (
      () => sub.length == 1 && method == 'PUT',
      () => _updateGroup(board, cubit, request, groupId, group, body, json, scheduleRebuild),
    ),
    (
      () => sub.length == 2 && sub[1] == 'panels' && method == 'POST',
      () => _addPanelsToGroup(board, cubit, request, groupId, body, json, error, scheduleRebuild),
    ),
    (
      () => sub.length == 2 && sub[1] == 'panels' && method == 'DELETE',
      () => _removePanelsFromGroup(board, cubit, request, groupId, body, json, error, scheduleRebuild),
    ),
    (
      () => sub.length == 2 && sub[1] == 'move' && method == 'POST',
      () => _moveGroup(board, cubit, request, groupId, body, json, scheduleRebuild),
    ),
    (
      () => sub.length == 2 && sub[1] == 'cycle-focus' && method == 'POST',
      () => _cycleGroupFocus(board, cubit, request, groupId, body, json, scheduleRebuild),
    ),
  ];
  for (final (matches, run) in routes) {
    if (matches()) return run();
  }

  return notFound(unknownRoute('group'));
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
shelf.Response _listGroups(
  BoardDocument board,
  shelf.Response Function(Object) json,
) {
  return json({
    'ok': true,
    'groups': board.groups.map((group) => group.toJson()).toList(),
  });
}

// POST /api/boards/:id/groups → create group
Future<shelf.Response> _createGroup(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final name = requestBody['name'] as String?;
  if (name == null || name.trim().isEmpty) {
    return error(missingField('name'));
  }
  final panelIds = _parsePanelIds(requestBody['panels']);
  final colorValue = _parseColor(requestBody['color']);
  await cubit.createGroup(
    board.id,
    name: name,
    panelIds: panelIds,
    color: colorValue,
  );
  scheduleRebuild();
  BoardDocument? updatedBoard;
  for (final candidate in cubit.state.boards) {
    if (candidate.id == board.id) {
      updatedBoard = candidate;
      break;
    }
  }
  BoardPanelGroup? created;
  final groups = updatedBoard?.groups;
  if (groups != null && groups.isNotEmpty) created = groups.last;
  return json({
    'ok': true,
    'message': 'Group "$name" created',
    'group': created?.toJson(),
  });
}

// DELETE /api/boards/:id/groups/:groupId
Future<shelf.Response> _deleteGroup(
  BoardDocument board,
  BoardCubit cubit,
  String groupId,
  shelf.Response Function(Object) json,
  void Function() scheduleRebuild,
) async {
  await cubit.deleteGroup(board.id, groupId);
  scheduleRebuild();
  return json(okJson({'message': 'Group deleted'}));
}

// PUT /api/boards/:id/groups/:groupId → rename, color, collapse
Future<shelf.Response> _updateGroup(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  String groupId,
  BoardPanelGroup group,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final newName = requestBody['name'] as String?;
  final colorRaw = requestBody['color'];
  final collapsed = requestBody['collapsed'] as bool?;
  if (newName != null) {
    await cubit.renameGroup(board.id, groupId, newName);
  }
  if (colorRaw != null) {
    await cubit.setGroupColor(board.id, groupId, _parseColor(colorRaw));
  }
  if (collapsed != null && collapsed != group.collapsed) {
    await cubit.toggleGroupCollapse(board.id, groupId);
  }
  scheduleRebuild();
  BoardDocument? updatedBoard;
  for (final candidate in cubit.state.boards) {
    if (candidate.id == board.id) {
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
  return json(okJson({'group': updated?.toJson()}));
}

// POST /api/boards/:id/groups/:groupId/panels → add panels
Future<shelf.Response> _addPanelsToGroup(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  String groupId,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final panelIds = _parsePanelIds(requestBody['panels']);
  if (panelIds.isEmpty) return error(missingField('panels'));
  await cubit.addPanelsToGroup(board.id, groupId, panelIds);
  scheduleRebuild();
  return json(okJson({'message': 'Panels added to group'}));
}

// DELETE /api/boards/:id/groups/:groupId/panels → remove panels
Future<shelf.Response> _removePanelsFromGroup(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  String groupId,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final panelIds = _parsePanelIds(requestBody['panels']);
  if (panelIds.isEmpty) return error(missingField('panels'));
  await cubit.removePanelsFromGroup(board.id, groupId, panelIds);
  scheduleRebuild();
  return json(okJson({'message': 'Panels removed from group'}));
}

// POST /api/boards/:id/groups/:groupId/move → move group by delta
Future<shelf.Response> _moveGroup(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  String groupId,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final dx = (requestBody['dx'] as num?)?.toDouble() ?? 0.0;
  final dy = (requestBody['dy'] as num?)?.toDouble() ?? 0.0;
  await cubit.moveGroup(board.id, groupId, Offset(dx, dy));
  scheduleRebuild();
  return json(okJson({'message': 'Group moved'}));
}

// POST /api/boards/:id/groups/:groupId/cycle-focus → cycle collapsed focus
Future<shelf.Response> _cycleGroupFocus(
  BoardDocument board,
  BoardCubit cubit,
  shelf.Request request,
  String groupId,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  void Function() scheduleRebuild,
) async {
  final requestBody = await body(request);
  final direction = (requestBody['direction'] as num?)?.toInt() ?? 1;
  await cubit.cycleGroupFocus(board.id, groupId, direction);
  scheduleRebuild();
  return json(okJson({'message': 'Group focus cycled'}));
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
