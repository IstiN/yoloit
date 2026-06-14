import 'package:equatable/equatable.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardState extends Equatable {
  const BoardState({
    this.boards = const [],
    this.activeBoardId,
    this.isLoaded = false,
    this.selectedPanelIds = const {},
  });

  final List<BoardDocument> boards;
  final String? activeBoardId;
  final bool isLoaded;
  final Set<String> selectedPanelIds;

  BoardDocument? get activeBoard {
    if (boards.isEmpty) return null;
    final activeId = activeBoardId;
    if (activeId == null) return boards.first;
    for (final board in boards) {
      if (board.id == activeId) return board;
    }
    return boards.first;
  }

  BoardState copyWith({
    List<BoardDocument>? boards,
    String? activeBoardId,
    bool clearActiveBoardId = false,
    bool? isLoaded,
    Set<String>? selectedPanelIds,
    bool clearSelection = false,
  }) {
    return BoardState(
      boards: boards ?? this.boards,
      activeBoardId:
          clearActiveBoardId ? null : (activeBoardId ?? this.activeBoardId),
      isLoaded: isLoaded ?? this.isLoaded,
      selectedPanelIds:
          clearSelection ? const {} : (selectedPanelIds ?? this.selectedPanelIds),
    );
  }

  @override
  List<Object?> get props => [boards, activeBoardId, isLoaded, selectedPanelIds];
}
