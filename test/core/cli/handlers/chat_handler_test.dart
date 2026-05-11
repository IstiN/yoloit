import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/chat_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.chat',
      title: 'Chat',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      state: state,
    );

void main() {
  final handler = const ChatCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.chat');
  });

  test('supportedActions', () {
    expect(handler.supportedActions,
        containsAll(['send', 'messages', 'config', 'clear']));
  });

  test('messages action returns messages', () async {
    final panel = _panel(state: {
      'messages': [
        {'role': 'user', 'content': 'hi'}
      ]
    });
    final r = await handler.handleAction('messages', {}, panel);
    expect(r.ok, isTrue);
    expect((r.data!['messages'] as List).length, 1);
  });

  test('send action adds message', () async {
    final panel = _panel(state: {'messages': []});
    final r = await handler.handleAction('send', {'message': 'hello'}, panel);
    expect(r.ok, isTrue);
    expect(r.stateUpdate!['messages'], isNotEmpty);
    final msg = (r.stateUpdate!['messages'] as List).last;
    expect(msg['content'], 'hello');
    expect(msg['role'], 'user');
  });

  test('send requires message', () async {
    final r = await handler.handleAction('send', {}, _panel());
    expect(r.ok, isFalse);
  });

  test('config returns provider info', () async {
    final panel = _panel(state: {'config': {'provider': 'openai', 'model': 'gpt-4'}});
    final r = await handler.handleAction('config', {}, panel);
    expect(r.ok, isTrue);
    expect(r.data!['config']['provider'], 'openai');
  });

  test('clear resets messages', () async {
    final panel = _panel(state: {
      'messages': [
        {'role': 'user', 'content': 'hi'}
      ]
    });
    final r = await handler.handleAction('clear', {}, panel);
    expect(r.ok, isTrue);
    expect(r.stateUpdate!['messages'], isEmpty);
  });
}
