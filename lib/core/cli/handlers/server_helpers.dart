import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardDocument? findBoard(BoardCubit cubit, String idOrName) {
  final boards = cubit.state.boards;
  final byId = boards.where((b) => b.id == idOrName).firstOrNull;
  if (byId != null) return byId;
  final byName =
      boards
          .where((b) => b.name.toLowerCase() == idOrName.toLowerCase())
          .firstOrNull;
  if (byName != null) return byName;
  return boards.where((b) => b.id.startsWith(idOrName)).firstOrNull;
}

BoardPanelInstance? findPanel(BoardDocument board, String idOrTitle) {
  final panels = board.panels;
  final byId = panels.where((p) => p.id == idOrTitle).firstOrNull;
  if (byId != null) return byId;
  final byTitle =
      panels
          .where((p) => p.title.toLowerCase() == idOrTitle.toLowerCase())
          .firstOrNull;
  if (byTitle != null) return byTitle;
  return panels.where((p) => p.id.startsWith(idOrTitle)).firstOrNull;
}
