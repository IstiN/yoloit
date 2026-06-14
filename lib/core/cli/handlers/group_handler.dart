import 'dart:async';
import 'dart:ui';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Handles `/api/boards/:id/groups/...` routes.
Future<shelf.Response> handleGroup(
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
}) async {
  // GET /api/boards/:id/groups → list groups
  if (sub.isEmpty && method == 'GET') {
    return json({
      'ok': true,
      'groups': board.groups.map((group) => group.toJson()).toList(),
    });
  }

  // POST /api/boards/:id/groups → create group
  if (sub.isEmpty && method == 'POST') {
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

  // /api/boards/:id/groups/:groupId/...
  if (sub.isEmpty) return notFound(unknownRoute('group'));
  final groupId = sub[0];
  BoardPanelGroup? group;
  for (final candidate in board.groups) {
    if (candidate.id == groupId) {
      group = candidate;
      break;
    }
  }
  if (group == null) {
    return notFound('Group not found: $groupId');
  }

  // DELETE /api/boards/:id/groups/:groupId
  if (sub.length == 1 && method == 'DELETE') {
    await cubit.deleteGroup(board.id, groupId);
    scheduleRebuild();
    return json(okJson({'message': 'Group deleted'}));
  }

  // PUT /api/boards/:id/groups/:groupId → rename, color, collapse
  if (sub.length == 1 && method == 'PUT') {
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
  if (sub.length == 2 && sub[1] == 'panels' && method == 'POST') {
    final requestBody = await body(request);
    final panelIds = _parsePanelIds(requestBody['panels']);
    if (panelIds.isEmpty) return error(missingField('panels'));
    await cubit.addPanelsToGroup(board.id, groupId, panelIds);
    scheduleRebuild();
    return json(okJson({'message': 'Panels added to group'}));
  }

  // DELETE /api/boards/:id/groups/:groupId/panels → remove panels
  if (sub.length == 2 && sub[1] == 'panels' && method == 'DELETE') {
    final requestBody = await body(request);
    final panelIds = _parsePanelIds(requestBody['panels']);
    if (panelIds.isEmpty) return error(missingField('panels'));
    await cubit.removePanelsFromGroup(board.id, groupId, panelIds);
    scheduleRebuild();
    return json(okJson({'message': 'Panels removed from group'}));
  }

  // POST /api/boards/:id/groups/:groupId/move → move group by delta
  if (sub.length == 2 && sub[1] == 'move' && method == 'POST') {
    final requestBody = await body(request);
    final dx = (requestBody['dx'] as num?)?.toDouble() ?? 0.0;
    final dy = (requestBody['dy'] as num?)?.toDouble() ?? 0.0;
    await cubit.moveGroup(board.id, groupId, Offset(dx, dy));
    scheduleRebuild();
    return json(okJson({'message': 'Group moved'}));
  }

  // POST /api/boards/:id/groups/:groupId/cycle-focus → cycle collapsed focus
  if (sub.length == 2 && sub[1] == 'cycle-focus' && method == 'POST') {
    final requestBody = await body(request);
    final direction = (requestBody['direction'] as num?)?.toInt() ?? 1;
    await cubit.cycleGroupFocus(board.id, groupId, direction);
    scheduleRebuild();
    return json(okJson({'message': 'Group focus cycled'}));
  }

  return notFound(unknownRoute('group'));
}

List<String> _parsePanelIds(dynamic value) {
  if (value == null) return const [];
  if (value is String) {
    return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}

int? _parseColor(dynamic value) {
  if (value == null || value == 'clear') return null;
  if (value is int) return value;
  if (value is String) {
    final color = parseColor(value);
    return color?.toARGB32();
  }
  return null;
}
