import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/cli/handlers/run_configs_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/data/run_bridge.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.run_configs',
      title: 'Run Configs',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

void main() {
  final handler = const RunConfigsCliHandler();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RunBridge.instance.attach(RunCubit());
  });

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
      expect(content['sessions'], <dynamic>[]);
      expect(content['isRunning'], false);
      expect(content.containsKey('group'), isTrue);
      expect(content.containsKey('activeSessionId'), isTrue);
    });

    test('returns populated state after config is added', () async {
      await RunBridge.instance.addConfig(
        name: 'Test',
        command: 'echo hi',
        group: 'p1',
      );
      final content = handler.getContent(_panel());
      expect((content['configurations'] as List).length, 1);
      expect(content['isRunning'], false);
    });
  });

  group('handleAction', () {
    test('list returns configurations data', () async {
      final r = await handler.handleAction('list', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.data!['configurations'], isEmpty);
    });

    test('add creates new config', () async {
      final r = await handler.handleAction('add', {
        'name': 'Flutter Run',
        'command': 'flutter run',
      }, _panel());
      expect(r.ok, isTrue);
      expect(r.message, contains('Flutter Run'));
      expect(r.data!['name'], 'Flutter Run');
      expect(r.data!['command'], 'flutter run');
      expect(r.data!['id'], isNotEmpty);
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
      final addResult = await handler.handleAction('add', {
        'name': 'Test',
        'command': 'echo hi',
      }, _panel());
      final id = addResult.data!['id'] as String;
      final r = await handler.handleAction('remove', {'id': id}, _panel());
      expect(r.ok, isTrue);
      expect(r.message, contains('removed'));
    });

    test('remove with invalid id returns error', () async {
      final r = await handler.handleAction('remove', {'id': 'nope'}, _panel());
      expect(r.ok, isFalse);
    });

    test('remove without id returns error', () async {
      final r = await handler.handleAction('remove', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('run with no configs returns error', () async {
      final r = await handler.handleAction('run', {}, _panel());
      expect(r.ok, isFalse);
    });

    test('output returns error when no session', () async {
      final r = await handler.handleAction('output', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('not found'));
    });

    test('config returns error when not found', () async {
      final r = await handler.handleAction('config', {'id': 'nope'}, _panel());
      expect(r.ok, isFalse);
    });

    test('config returns details when found', () async {
      await handler.handleAction('add', {
        'name': 'MyTest',
        'command': 'echo hello',
      }, _panel());
      final r = await handler.handleAction('config', {'name': 'MyTest'}, _panel());
      expect(r.ok, isTrue);
      expect(r.data!['name'], 'MyTest');
      expect(r.data!['command'], 'echo hello');
    });

    test('unknown action returns error', () async {
      final r = await handler.handleAction('unknown', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Unknown'));
    });
  });
}

