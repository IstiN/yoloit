import 'package:yoloit/features/board/model/board_models.dart';

enum BoardRedoKind {
  recreatePanel,
  restorePanel,
  deletePanel,
}

/// Captures one redo step pushed when the user undoes a panel history batch.
class BoardRedoEntry {
  const BoardRedoEntry.recreate(this.panel)
    : kind = BoardRedoKind.recreatePanel,
      panelId = null;

  const BoardRedoEntry.restore(this.panel)
    : kind = BoardRedoKind.restorePanel,
      panelId = null;

  const BoardRedoEntry.delete(this.panelId)
    : kind = BoardRedoKind.deletePanel,
      panel = null;

  final BoardRedoKind kind;
  final BoardPanelInstance? panel;
  final String? panelId;
}
