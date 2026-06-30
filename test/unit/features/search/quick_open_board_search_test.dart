import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/search/utils/quick_open_search.dart';

void main() {
  test('matchBoardsForQuickOpen matches board names and ids', () {
    const boards = [
      BoardDocument(
        id: 'home',
        name: 'Home Board',
        viewport: BoardViewport(scale: 1),
      ),
      BoardDocument(
        id: 'roadmap',
        name: 'Product Roadmap',
        viewport: BoardViewport(scale: 1),
      ),
    ];

    expect(matchBoardsForQuickOpen(boards, 'roadmap').single.id, 'roadmap');
    expect(matchBoardsForQuickOpen(boards, 'home').single.id, 'home');
    expect(matchBoardsForQuickOpen(boards, 'missing'), isEmpty);
  });
}
