import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/cli_server_http.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> boardHistoryCliPayload({
  required bool ok,
  required String resultKey,
  required int redoDepth,
  required String successMessage,
  required String failureMessage,
  Map<String, dynamic>? boardSummary,
}) {
  return {
    'ok': ok,
    resultKey: ok,
    'redoDepth': redoDepth,
    'message': ok ? successMessage : failureMessage,
    if (boardSummary != null) 'board': boardSummary,
  };
}

Future<shelf.Response> boardHistoryShelfResponse({
  required Future<bool> Function() action,
  required void Function() onApplied,
  required BoardCubit cubit,
  required BoardDocument board,
  required String resultKey,
  required String successMessage,
  required String failureMessage,
  required Map<String, dynamic> Function(BoardDocument board, {String? activeId})
  summarizeBoard,
}) async {
  final ok = await action();
  if (ok) {
    onApplied();
  }
  final updated =
      cubit.state.boards.where((entry) => entry.id == board.id).firstOrNull;
  return cliJson(
    boardHistoryCliPayload(
      ok: ok,
      resultKey: resultKey,
      redoDepth: cubit.redoDepthForBoard(board.id),
      successMessage: successMessage,
      failureMessage: failureMessage,
      boardSummary:
          updated == null
              ? null
              : summarizeBoard(updated, activeId: cubit.state.activeBoardId),
    ),
  );
}

Future<Map<String, dynamic>> yamlBoardHistoryOp({
  required BoardCubit cubit,
  required BoardDocument board,
  required String op,
  required void Function() onApplied,
}) async {
  final undo = op == 'board.undo';
  final ok = await (undo
      ? cubit.undoLatestPanelHistory(board.id)
      : cubit.redoLatestPanelHistory(board.id));
  if (ok) {
    onApplied();
  }
  return boardHistoryCliPayload(
    ok: ok,
    resultKey: undo ? 'undone' : 'redone',
    redoDepth: cubit.redoDepthForBoard(board.id),
    successMessage:
        undo
            ? 'Undid latest panel change'
            : 'Redid latest undone panel change',
    failureMessage:
        undo
            ? 'No restorable panel history yet'
            : 'No redoable panel history yet',
  );
}
