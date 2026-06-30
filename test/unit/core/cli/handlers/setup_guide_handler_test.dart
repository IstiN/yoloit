// covers-write: board.setup_guide
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/setup_guide_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'setup-1',
      type: 'board.setup_guide',
      title: 'Setup',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
      state: state,
    );

void main() {
  const handler = SetupGuideCliHandler();

  test('select and unselect package ids', () async {
    final select = await handler.handleAction(
      'select',
      {'packageId': 'codex'},
      _panel(state: {'selectedPackageIds': ['git']}),
    );
    expect(select.stateUpdate!['selectedPackageIds'], ['git', 'codex']);

    final unselect = await handler.handleAction(
      'unselect',
      {'packageId': 'git'},
      _panel(state: {'selectedPackageIds': ['git', 'codex']}),
    );
    expect(unselect.stateUpdate!['selectedPackageIds'], ['codex']);
  });

  test('set-selected replaces list', () async {
    final result = await handler.handleAction(
      'set-selected',
      {'packageIds': ['tmux', 'codex']},
      _panel(),
    );
    expect(result.stateUpdate!['selectedPackageIds'], ['tmux', 'codex']);
  });
}
