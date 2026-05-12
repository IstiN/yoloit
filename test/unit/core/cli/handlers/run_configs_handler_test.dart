import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/run_configs_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.run_configs',
      title: 'Run Configs',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

Map<String, dynamic> _config({
  String id = 'cfg1',
  String name = 'Test',
  String command = 'echo hi',
  String status = 'idle',
}) => {
  'id': id,
  'name': name,
  'command': command,
  'workingDir': '',
  'envVars': <String, String>{},
  'status': status,
  'output': '',
};

void main() {
  final handler = const RunConfigsCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.run_configs');
  });

  test('supportedActions contains expected actions', () {
    expect(
      handler.supportedActions,
      containsAll(['list', 'add', 'remove', 'run', 'stop', 'output', 'config']),
    );
  });

  group('getContent', () {
    test('returns correct structure with defaults', () {
      final content = handler.getContent(_panel());
      expect(content['configurations'], <dynamic>[]);
      expect(content['activeConfigId'], '');
      expect(content['isRunning'], false);
    });

    test('returns populated state', () {
      final cfg = _config();
      final panel = _panel(
        state: {
          'configurations': [cfg],
          'activeConfigId': 'cfg1',
          'isRunning': true,
        },
      );
      final content = handler.getContent(panel);
      expect((content['configurations'] as List).length, 1);
      expect(content['activeConfigId'], 'cfg1');
      expect(content['isRunning'], true);
    });
  });

  group('handleAction', () {
    test('list returns getContent data', () async {
      final panel = _panel(
        state: {
          'configurations': [_config()],
        },
      );
      final r = await handler.handleAction('list', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['configurations'], isNotEmpty);
    });

    test('add creates new config', () async {
      final r = await handler.handleAction('add', {
        'name': 'Flutter Run',
        'command': 'flutter run',
      }, _panel());
      expect(r.ok, isTrue);
      expect(r.message, contains('Flutter Run'));
      final configs = r.stateUpdate!['configurations'] as List;
      expect(configs.length, 1);
      expect(configs.first['name'], 'Flutter Run');
      expect(configs.first['command'], 'flutter run');
      expect(configs.first['status'], 'idle');
      expect(configs.first['id'], isNotEmpty);
      expect(r.stateUpdate!['activeConfigId'], configs.first['id']);
    });

    test('add without name returns error', () async {
      final r = await handler.handleAction('add', {
        'command': 'echo hi',
      }, _panel());
      expect(r.ok, isFalse);
    });

    test('add without command returns error', () async {
      final r = await handler.handleAction('add', {'name': 'Test'}, _panel());
      expect(r.ok, isFalse);
    });

    test('remove removes config by id', () async {
      final panel = _panel(
        state: {
          'configurations': [
            _config(id: 'cfg1'),
            _config(id: 'cfg2', name: 'Other'),
          ],
          'activeConfigId': 'cfg1',
        },
      );
      final r = await handler.handleAction('remove', {'id': 'cfg1'}, panel);
      expect(r.ok, isTrue);
      final configs = r.stateUpdate!['configurations'] as List;
      expect(configs.length, 1);
      expect(configs.first['id'], 'cfg2');
      // active was removed, so it should be cleared
      expect(r.stateUpdate!['activeConfigId'], '');
    });

    test('remove with invalid id returns error', () async {
      final panel = _panel(
        state: {
          'configurations': [_config()],
        },
      );
      final r = await handler.handleAction('remove', {'id': 'nope'}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('not found'));
    });

    test('remove without id returns error', () async {
      final r = await handler.handleAction('remove', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('run sets config status to running', () async {
      final panel = _panel(
        state: {
          'configurations': [_config(id: 'cfg1')],
          'activeConfigId': 'cfg1',
        },
      );
      final r = await handler.handleAction('run', {'id': 'cfg1'}, panel);
      expect(r.ok, isTrue);
      final configs = r.stateUpdate!['configurations'] as List;
      expect(configs.first['status'], 'running');
      expect(r.stateUpdate!['isRunning'], true);
    });

    test('run with invalid id returns error', () async {
      final panel = _panel(
        state: {
          'configurations': [_config()],
        },
      );
      final r = await handler.handleAction('run', {'id': 'nope'}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('not found'));
    });

    test('run with no id and no active returns error', () async {
      final r = await handler.handleAction('run', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('No configuration selected'));
    });

    test('stop sets config status to idle', () async {
      final panel = _panel(
        state: {
          'configurations': [_config(id: 'cfg1', status: 'running')],
          'activeConfigId': 'cfg1',
          'isRunning': true,
        },
      );
      final r = await handler.handleAction('stop', {'id': 'cfg1'}, panel);
      expect(r.ok, isTrue);
      final configs = r.stateUpdate!['configurations'] as List;
      expect(configs.first['status'], 'idle');
      expect(r.stateUpdate!['isRunning'], false);
    });

    test('stop with invalid id returns error', () async {
      final panel = _panel(
        state: {
          'configurations': [_config()],
          'activeConfigId': 'cfg1',
        },
      );
      final r = await handler.handleAction('stop', {'id': 'nope'}, panel);
      expect(r.ok, isFalse);
    });

    test('output returns config output', () async {
      final cfg = _config()..['output'] = 'hello world';
      final panel = _panel(
        state: {
          'configurations': [cfg],
          'activeConfigId': 'cfg1',
        },
      );
      final r = await handler.handleAction('output', {'id': 'cfg1'}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['output'], 'hello world');
    });

    test('config returns full config details', () async {
      final panel = _panel(
        state: {
          'configurations': [_config()],
          'activeConfigId': 'cfg1',
        },
      );
      final r = await handler.handleAction('config', {'id': 'cfg1'}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['name'], 'Test');
      expect(r.data!['command'], 'echo hi');
    });

    test('unknown action returns error', () async {
      final r = await handler.handleAction('unknown', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Unknown'));
    });
  });
}
