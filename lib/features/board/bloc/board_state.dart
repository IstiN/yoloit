import 'package:equatable/equatable.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardState extends Equatable {
  const BoardState({
    this.boards = const [],
    this.activeBoardId,
    this.isLoaded = false,
    this.selectedPanelIds = const {},
    this.yoloAssistantAnchorPanelId,
    this.yoloAssistantStartMic = false,
    this.panelLockConflictPanelId,
    this.panelLockConflictActorId,
  });

  final List<BoardDocument> boards;
  final String? activeBoardId;
  final bool isLoaded;
  final Set<String> selectedPanelIds;
  final String? yoloAssistantAnchorPanelId;
  final bool yoloAssistantStartMic;
  final String? panelLockConflictPanelId;
  final String? panelLockConflictActorId;

  List<BoardDocument> get activeBoards =>
      boards.where((board) => !board.archived).toList();

  List<BoardDocument> get archivedBoards =>
      boards.where((board) => board.archived).toList();

  BoardDocument? get activeBoard {
    if (boards.isEmpty) return null;
    final activeId = activeBoardId;
    if (activeId == null) {
      return activeBoards.isNotEmpty ? activeBoards.first : boards.first;
    }
    for (final board in boards) {
      if (board.id == activeId) return board;
    }
    return activeBoards.isNotEmpty ? activeBoards.first : boards.first;
  }

  BoardState copyWith({
    List<BoardDocument>? boards,
    String? activeBoardId,
    bool clearActiveBoardId = false,
    bool? isLoaded,
    Set<String>? selectedPanelIds,
    bool clearSelection = false,
    String? yoloAssistantAnchorPanelId,
    bool clearYoloAssistantAnchor = false,
    bool? yoloAssistantStartMic,
    String? panelLockConflictPanelId,
    bool clearPanelLockConflict = false,
    String? panelLockConflictActorId,
  }) {
    return BoardState(
      boards: boards ?? this.boards,
      activeBoardId:
          clearActiveBoardId ? null : (activeBoardId ?? this.activeBoardId),
      isLoaded: isLoaded ?? this.isLoaded,
      selectedPanelIds:
          clearSelection ? const {} : (selectedPanelIds ?? this.selectedPanelIds),
      yoloAssistantAnchorPanelId:
          clearYoloAssistantAnchor
              ? null
              : (yoloAssistantAnchorPanelId ?? this.yoloAssistantAnchorPanelId),
      yoloAssistantStartMic:
          yoloAssistantStartMic ?? this.yoloAssistantStartMic,
      panelLockConflictPanelId: clearPanelLockConflict
          ? null
          : (panelLockConflictPanelId ?? this.panelLockConflictPanelId),
      panelLockConflictActorId: clearPanelLockConflict
          ? null
          : (panelLockConflictActorId ?? this.panelLockConflictActorId),
    );
  }

  @override
  List<Object?> get props => [
    boards,
    activeBoardId,
    isLoaded,
    selectedPanelIds,
    yoloAssistantAnchorPanelId,
    yoloAssistantStartMic,
    panelLockConflictPanelId,
    panelLockConflictActorId,
  ];
}
