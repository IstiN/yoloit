import 'dart:convert';

import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Remote-diff helpers extracted from `BoardCubit` to keep the cubit under
/// the pre-commit file-size budget (2800 lines). Pure functions — no state.

/// Returns remote boards whose JSON differs from their [previousBoards]
/// counterpart. Serializes each previous remote board once (the old form
/// ran jsonEncode twice per comparison).
List<BoardDocument> changedRemoteBoards({
  required List<BoardDocument> previousBoards,
  required List<BoardDocument> nextBoards,
}) {
  final previousJsonById = <String, String>{
    for (final board in previousBoards)
      if (remoteInfoForBoard(board) != null)
        board.id: jsonEncode(boardToRemoteJson(board)),
  };
  return nextBoards
      .where((board) {
        if (remoteInfoForBoard(board) == null) return false;
        final previousJson = previousJsonById[board.id];
        if (previousJson == null) return false;
        return previousJson != jsonEncode(boardToRemoteJson(board));
      })
      .toList(growable: false);
}

/// Timestamp-based unique id for boards/panels (`prefix-<micros>`).
String boardNextId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';
