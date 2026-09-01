part of 'board_cubit.dart';

/// Metadata mutation helpers for [BoardCubit] split out to keep the main
/// cubit file under the repository line-count guard.
extension BoardCubitIconMutations on BoardCubit {
  /// Updates the board's default folder.
  Future<void> updateBoardDefaultFolder(
    String id,
    String? defaultFolder,
  ) async {
    await _updateBoard(
      id,
      (board) {
        final trimmed = defaultFolder?.trim() ?? '';
        final metadata = Map<String, dynamic>.from(board.metadata);
        if (trimmed.isEmpty) {
          metadata.remove('defaultFolder');
        } else {
          metadata['defaultFolder'] = trimmed;
        }
        return board.copyWith(metadata: metadata);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: id,
            type: 'board.metadataUpdated',
            entityType: 'board',
            entityId: id,
            revision: revision,
            before: {'metadata': before.metadata},
            after: {'metadata': after.metadata},
          ),
    );
  }

  /// Sets (or clears, when [icon] is `null`) the board icon override shown in
  /// the boards overview and the toolbar board switcher.
  Future<void> updateBoardIcon(String id, BoardIconSpec? icon) async {
    await _updateBoard(
      id,
      (board) => board.copyWithIcon(icon),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: id,
            type: 'board.metadataUpdated',
            entityType: 'board',
            entityId: id,
            revision: revision,
            before: {'metadata': before.metadata},
            after: {'metadata': after.metadata},
          ),
    );
  }
}
