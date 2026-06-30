// covers-write: board.diff.preview
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/diff_preview_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'diff-1',
      type: 'board.diff.preview',
      title: 'Diff',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 500),
      state: state,
    );

void main() {
  const handler = DiffPreviewCliHandler();

  test('open sets file path', () async {
    final result = await handler.handleAction(
      'open',
      {'path': '/repo/lib/main.dart', 'title': 'main.dart'},
      _panel(),
    );
    expect(result.ok, isTrue);
    expect(result.stateUpdate!['filePath'], '/repo/lib/main.dart');
    expect(result.stateUpdate!['title'], 'main.dart');
  });

  test('set-root updates rootPath', () async {
    final result = await handler.handleAction(
      'set-root',
      {'rootPath': '/repo'},
      _panel(),
    );
    expect(result.stateUpdate!['rootPath'], '/repo');
  });
}
