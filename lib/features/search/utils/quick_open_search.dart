import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';

/// Returns boards whose name or id matches [rawQuery].
List<BoardDocument> matchBoardsForQuickOpen(
  List<BoardDocument> boards,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];
  final queries = FuzzyMatcher.candidates(query);
  return [
    for (final board in boards)
      if (FuzzyMatcher.bestScore(board.name, queries) != null ||
          FuzzyMatcher.bestScore(board.id, queries) != null)
        board,
  ];
}
