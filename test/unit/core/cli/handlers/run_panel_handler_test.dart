// covers-write: board.run
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/run_panel_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'run-panel-1',
      type: 'board.run',
      title: 'Run',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

void main() {
  const handler = RunPanelCliHandler();

  test('typeId is board.run', () {
    expect(handler.typeId, 'board.run');
  });

  test('get returns panel state', () async {
    final result = await handler.handleAction(
      'get',
      {},
      _panel(state: {
        'group': 'review',
        'activeSessionId': 'sess_1',
        'hiddenSessionIds': ['sess_2'],
      }),
    );
    expect(result.ok, isTrue);
    expect(result.data!['group'], 'review');
    expect(result.data!['activeSessionId'], 'sess_1');
    expect(result.data!['hiddenSessionIds'], ['sess_2']);
  });

  test('set-group updates state', () async {
    final result = await handler.handleAction(
      'set-group',
      {'group': 'dev'},
      _panel(),
    );
    expect(result.ok, isTrue);
    expect(result.stateUpdate!['group'], 'dev');
  });

  test('select-session and clear-session', () async {
    final select = await handler.handleAction(
      'select-session',
      {'sessionId': 'sess_9'},
      _panel(),
    );
    expect(select.stateUpdate!['activeSessionId'], 'sess_9');

    final clear = await handler.handleAction('clear-session', {}, _panel());
    expect(clear.stateUpdate!['activeSessionId'], isNull);
  });
}
