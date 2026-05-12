import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/assistant_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.yolo_assistant',
      title: 'Assistant',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 560),
      state: state,
    );

void main() {
  final handler = const AssistantCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.yolo_assistant');
  });

  test('supportedActions contains expected actions', () {
    expect(
      handler.supportedActions,
      containsAll([
        'send',
        'messages',
        'clear',
        'skills',
        'add-skill',
        'remove-skill',
        'mode',
        'voice-start',
        'voice-stop',
      ]),
    );
  });

  group('getContent', () {
    test('returns correct structure with defaults', () {
      final content = handler.getContent(_panel());
      expect(content['mode'], 'text');
      expect(content['isListening'], false);
      expect(content['isSpeaking'], false);
      expect(content['activeSkills'], <dynamic>[]);
      expect(content['messageCount'], 0);
      expect(content['messages'], <dynamic>[]);
    });

    test('returns populated state', () {
      final panel = _panel(
        state: {
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
          'activeSkills': ['Terminal'],
          'mode': 'voice',
          'isListening': true,
          'isSpeaking': false,
        },
      );
      final content = handler.getContent(panel);
      expect(content['mode'], 'voice');
      expect(content['isListening'], true);
      expect(content['messageCount'], 1);
      expect((content['messages'] as List).first['role'], 'user');
    });
  });

  group('handleAction', () {
    test('send adds message to list', () async {
      final panel = _panel(state: {'messages': []});
      final r = await handler.handleAction('send', {'text': 'hello'}, panel);
      expect(r.ok, isTrue);
      expect(r.message, 'Message sent');
      final msgs = r.stateUpdate!['messages'] as List;
      expect(msgs.length, 1);
      expect(msgs.last['content'], 'hello');
      expect(msgs.last['role'], 'user');
    });

    test('send also accepts "message" key', () async {
      final panel = _panel(state: {'messages': []});
      final r = await handler.handleAction('send', {'message': 'hi'}, panel);
      expect(r.ok, isTrue);
      final msgs = r.stateUpdate!['messages'] as List;
      expect(msgs.last['content'], 'hi');
    });

    test('send without text returns error', () async {
      final r = await handler.handleAction('send', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('send with empty text returns error', () async {
      final r = await handler.handleAction('send', {'text': ''}, _panel());
      expect(r.ok, isFalse);
    });

    test('messages returns all messages', () async {
      final panel = _panel(
        state: {
          'messages': [
            {'role': 'user', 'content': 'hi'},
            {'role': 'assistant', 'content': 'hello'},
          ],
        },
      );
      final r = await handler.handleAction('messages', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['total'], 2);
      expect((r.data!['messages'] as List).length, 2);
    });

    test('messages respects limit', () async {
      final panel = _panel(
        state: {
          'messages': [
            {'role': 'user', 'content': 'one'},
            {'role': 'user', 'content': 'two'},
            {'role': 'user', 'content': 'three'},
          ],
        },
      );
      final r = await handler.handleAction('messages', {'limit': 1}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['total'], 3);
      expect((r.data!['messages'] as List).length, 1);
    });

    test('clear empties messages', () async {
      final panel = _panel(
        state: {
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      final r = await handler.handleAction('clear', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['messages'], isEmpty);
    });

    test('skills returns active skills list', () async {
      final panel = _panel(
        state: {
          'activeSkills': ['Terminal', 'Web Search'],
        },
      );
      final r = await handler.handleAction('skills', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['activeSkills'], ['Terminal', 'Web Search']);
    });

    test('skills returns empty list by default', () async {
      final r = await handler.handleAction('skills', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.data!['activeSkills'], <String>[]);
    });

    test('add-skill adds skill', () async {
      final panel = _panel(
        state: {
          'activeSkills': ['Terminal'],
        },
      );
      final r = await handler.handleAction('add-skill', {
        'skill': 'Web Search',
      }, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['activeSkills'], contains('Web Search'));
      expect(r.stateUpdate!['activeSkills'], contains('Terminal'));
    });

    test('add-skill rejects duplicate', () async {
      final panel = _panel(
        state: {
          'activeSkills': ['Terminal'],
        },
      );
      final r = await handler.handleAction('add-skill', {
        'skill': 'Terminal',
      }, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('already active'));
    });

    test('add-skill without skill returns error', () async {
      final r = await handler.handleAction('add-skill', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('remove-skill removes skill', () async {
      final panel = _panel(
        state: {
          'activeSkills': ['Terminal', 'Web Search'],
        },
      );
      final r = await handler.handleAction('remove-skill', {
        'skill': 'Terminal',
      }, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['activeSkills'], isNot(contains('Terminal')));
      expect(r.stateUpdate!['activeSkills'], contains('Web Search'));
    });

    test('remove-skill for non-active skill returns error', () async {
      final panel = _panel(
        state: {
          'activeSkills': ['Terminal'],
        },
      );
      final r = await handler.handleAction('remove-skill', {
        'skill': 'Nope',
      }, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('not active'));
    });

    test('remove-skill without skill returns error', () async {
      final r = await handler.handleAction('remove-skill', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('mode switches to voice', () async {
      final r = await handler.handleAction('mode', {'mode': 'voice'}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['mode'], 'voice');
      expect(r.stateUpdate!['isListening'], false);
      expect(r.stateUpdate!['isSpeaking'], false);
    });

    test('mode switches to text', () async {
      final panel = _panel(state: {'mode': 'voice'});
      final r = await handler.handleAction('mode', {'mode': 'text'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['mode'], 'text');
    });

    test('mode rejects invalid value', () async {
      final r = await handler.handleAction('mode', {
        'mode': 'invalid',
      }, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('text'));
      expect(r.message, contains('voice'));
    });

    test('voice-start enables listening', () async {
      final r = await handler.handleAction('voice-start', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['mode'], 'voice');
      expect(r.stateUpdate!['isListening'], true);
    });

    test('voice-stop disables listening', () async {
      final panel = _panel(state: {'isListening': true});
      final r = await handler.handleAction('voice-stop', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isListening'], false);
    });

    test('unknown action returns error', () async {
      final r = await handler.handleAction('unknown', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Unknown'));
    });
  });
}
