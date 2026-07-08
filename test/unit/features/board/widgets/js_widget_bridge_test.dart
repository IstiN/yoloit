// covers-write: board.widget.custom
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/widgets/js_widget_bridge.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsWidgetBridge', () {
    late List<Map<String, dynamic>> renders;
    late List<String> titles;
    late List<Map<String, dynamic>> storageUpdates;
    late List<String> logs;
    late Map<String, dynamic> resolves;
    late Map<String, dynamic> fetches;
    late Map<String, dynamic> secretReads;
    late Map<String, dynamic> secretWrites;
    late Map<String, dynamic> loadAssets;
    late Map<String, dynamic> execs;
    late List<String> intervalTicks;
    late List<Map<String, dynamic>> rafTicks;
    late bool disposed;

    JsWidgetBridge createBridge({
      Map<String, dynamic> initialStorage = const {},
    }) {
      renders = [];
      titles = [];
      storageUpdates = [];
      logs = [];
      resolves = {};
      fetches = {};
      secretReads = {};
      secretWrites = {};
      loadAssets = {};
      execs = {};
      intervalTicks = [];
      rafTicks = [];
      disposed = false;
      return JsWidgetBridge(
        widgetId: 'w1',
        onRender: renders.add,
        onSetTitle: titles.add,
        onStorageUpdate: storageUpdates.add,
        onLog: logs.add,
        isDisposed: () => disposed,
        resolveCallback: (id, value) => resolves[id] = value,
        fetchHandler: (id, url, method, headers) async {
          fetches[id] = {'url': url, 'method': method, 'headers': headers};
        },
        secretsGetHandler: (id, key) async {
          secretReads[id] = key;
        },
        secretsSetHandler: (id, key, value) async {
          secretWrites[id] = {'key': key, 'value': value};
        },
        loadAssetHandler: (id, path) async {
          loadAssets[id] = path;
        },
        execHandler: (id, cmd) async {
          execs[id] = cmd;
        },
        intervalTickHandler: intervalTicks.add,
        rafTickHandler: (id, elapsedMs) => rafTicks.add({'id': id, 'elapsedMs': elapsedMs}),
        initialStorage: initialStorage,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await WidgetPermissionsService.instance.load();
    });

    test('dispatches render and forwards the UI tree', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_render', {'type': 'text', 'value': 'hi'});
      expect(renders, [
        {'type': 'text', 'value': 'hi'},
      ]);
    });

    test('dispatches set_title', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_set_title', 'My Title');
      expect(titles, ['My Title']);
    });

    test('dispatches log', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_log', 'hello');
      expect(logs, ['hello']);
    });

    test('dispatches export_state', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_export_state', {'count': 3});
      expect(bridge.exportedState, {'count': 3});
    });

    test('dispatches storage_set and notifies listeners', () async {
      final bridge = createBridge(initialStorage: {'a': 1});
      await bridge.dispatch(
        '__yoloit_storage_set',
        {'key': 'b', 'value': 2},
      );
      expect(storageUpdates, [
        {'a': 1, 'b': 2},
      ]);
    });

    test('dispatches storage_get and resolves cached value', () async {
      final bridge = createBridge(initialStorage: {'key': 'value'});
      await bridge.dispatch('__yoloit_storage_get', {'id': 'r1', 'key': 'key'});
      expect(resolves['r1'], 'value');
    });

    test('storage permission denial blocks reads and writes', () async {
      await WidgetPermissionsService.instance.setAllowed('storage', false);
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_storage_set', {'key': 'x', 'value': 1});
      await bridge.dispatch('__yoloit_storage_get', {'id': 'r1', 'key': 'x'});
      expect(storageUpdates, isEmpty);
      expect(resolves['r1'], contains('__error'));
    });

    test('dispatches fetch and delegates to handler', () async {
      final bridge = createBridge();
      await bridge.dispatch(
        '__yoloit_fetch',
        {
          'id': 'f1',
          'url': 'https://example.com/api',
          'method': 'POST',
          'headers': {'X-Custom': '1'},
        },
      );
      expect(fetches['f1'], {
        'url': 'https://example.com/api',
        'method': 'POST',
        'headers': {'X-Custom': '1'},
      });
    });

    test('fetch permission denial resolves with error', () async {
      await WidgetPermissionsService.instance.setAllowed('fetch', false);
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_fetch', {'id': 'f1', 'url': 'https://x'});
      expect(fetches, isEmpty);
      expect(resolves['f1'], contains('__error'));
    });

    test('dispatches secrets and delegates to handlers', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_secrets_get', {'id': 's1', 'key': 'token'});
      await bridge.dispatch(
        '__yoloit_secrets_set',
        {'id': 's2', 'key': 'token', 'value': 'abc'},
      );
      expect(secretReads['s1'], 'token');
      expect(secretWrites['s2'], {'key': 'token', 'value': 'abc'});
    });

    test('dispatches load_asset and delegates to handler', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_load_asset', {'id': 'l1', 'path': 'data.json'});
      expect(loadAssets['l1'], 'data.json');
    });

    test('dispatches exec and delegates to handler', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_exec', {'id': 'e1', 'cmd': 'yoloit boards'});
      expect(execs['e1'], 'yoloit boards');
    });

    test('callEvent completes when event_done arrives', () async {
      final bridge = createBridge();
      var sent = false;
      final future = bridge.callEvent(() => sent = true);
      expect(sent, isTrue);
      await bridge.dispatch('__yoloit_event_done', {});
      await future;
    });

    test('callEvent completes on event_done with error', () async {
      final bridge = createBridge();
      final future = bridge.callEvent(() {});
      await bridge.dispatch('__yoloit_event_done', {'error': 'boom'});
      await future;
    });

    test('setInterval produces ticks and clearInterval stops them', () async {
      final bridge = createBridge();
      await bridge.dispatch(
        '__yoloit_set_interval',
        {'id': 'iv1', 'ms': 10},
      );
      await Future.delayed(const Duration(milliseconds: 35));
      expect(intervalTicks.where((id) => id == 'iv1').length, greaterThanOrEqualTo(2));

      await bridge.dispatch('__yoloit_clear_interval', 'iv1');
      final countAfterClear = intervalTicks.where((id) => id == 'iv1').length;
      await Future.delayed(const Duration(milliseconds: 30));
      expect(
        intervalTicks.where((id) => id == 'iv1').length,
        countAfterClear,
      );
      bridge.dispose();
    });

    testWidgets(
      'requestAnimationFrame produces ticks and cancelAnimationFrame stops them',
      (tester) async {
        final bridge = createBridge();
        await bridge.dispatch('__yoloit_raf', {'id': 'raf1'});
        await tester.pump(const Duration(milliseconds: 100));
        expect(rafTicks.where((t) => t['id'] == 'raf1').length, greaterThanOrEqualTo(1));

        await bridge.dispatch('__yoloit_caf', 'raf1');
        final countAfterCancel = rafTicks.where((t) => t['id'] == 'raf1').length;
        await tester.pump(const Duration(milliseconds: 60));
        expect(rafTicks.where((t) => t['id'] == 'raf1').length, countAfterCancel);
        bridge.dispose();
      },
    );

    test('dispose cancels pending timers and completers', () async {
      final bridge = createBridge();
      await bridge.dispatch('__yoloit_set_interval', {'id': 'iv1', 'ms': 10});
      bridge.dispose();
      final count = intervalTicks.where((id) => id == 'iv1').length;
      await Future.delayed(const Duration(milliseconds: 30));
      expect(intervalTicks.where((id) => id == 'iv1').length, count);
    });

    test('isDisposed guards dispatch', () async {
      final bridge = createBridge();
      disposed = true;
      await bridge.dispatch('__yoloit_render', {'type': 'text'});
      expect(renders, isEmpty);
    });
  });
}
