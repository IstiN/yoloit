@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsWidgetEngine web worker', () {
    late List<Map<String, dynamic>> renders;
    late List<String> titles;
    late List<Map<String, dynamic>> storageUpdates;
    late JsWidgetEngine engine;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await WidgetPermissionsService.instance.load();
      renders = [];
      titles = [];
      storageUpdates = [];
      engine = JsWidgetEngine(
        widgetId: 'test-widget',
        onRender: renders.add,
        onSetTitle: titles.add,
        onStorageUpdate: storageUpdates.add,
        initialStorage: {'count': 0},
        initialTheme: {'isDark': false, 'bg': '#ffffff'},
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('worker starts and widget renders', () async {
      await engine.run('yoloit.render({type:"text",data:"hello"});');
      await pumpEventQueue();
      expect(renders, isNotEmpty);
      expect(renders.last['data'], 'hello');
    });

    test('setTitle is forwarded', () async {
      await engine.run('yoloit.panel.setTitle("Updated");');
      await pumpEventQueue();
      expect(titles, ['Updated']);
    });

    test('storage.set updates panel storage', () async {
      await engine.run('''
yoloit.storage.set('count', 5);
yoloit.render({type:'text',data:'done'});
''');
      await pumpEventQueue();
      expect(storageUpdates, isNotEmpty);
      expect(storageUpdates.last['count'], 5);
    });

    test('callEvent invokes widget handler', () async {
      await engine.run('''
yoloit.onEvent(function(actionId, payload) {
  if (actionId === 'tap') {
    yoloit.render({type:'text',data:'tapped:' + payload.key});
  }
});
yoloit.render({type:'text',data:'ready'});
''');
      await pumpEventQueue();
      expect(renders.last['data'], 'ready');

      await engine.callEvent('tap', {'key': 'abc'});
      await pumpEventQueue();
      expect(renders.last['data'], 'tapped:abc');
    });

    test('logs are captured', () async {
      await engine.run('console.log("from widget");');
      await pumpEventQueue();
      final logs = engine.flushLogs();
      expect(logs.map((l) => l['msg']), contains('from widget'));
    });

    test('dispose terminates worker', () async {
      await engine.run('yoloit.render({type:"text",data:"x"});');
      await engine.dispose();
      // After disposal, callEvent should be a no-op.
      await engine.callEvent('tap');
      expect(renders.length, 1);
    });
  });
}

Future<void> pumpEventQueue() => Future.delayed(Duration.zero);
