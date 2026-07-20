// covers-write: board.widget.custom
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

class FakeJsWidgetEngineBackend extends JsWidgetEngineBackend {
  FakeJsWidgetEngineBackend({required JsRuntimeConfig config})
    : _runtimeConfig = config;

  final JsRuntimeConfig _runtimeConfig;

  bool disposed = false;
  int runCount = 0;
  String? lastJs;

  @override
  Future<void> init() async {}

  @override
  Future<void> run(
    String widgetJs, {
    String? hostBootstrapJs,
    Map<String, dynamic> initialTheme = const {},
  }) async {
    runCount++;
    lastJs = widgetJs;
  }

  @override
  Future<void> callEvent(String actionId, [Map<String, dynamic>? payload]) async {}

  @override
  void updateTheme(Map<String, dynamic> colors) {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  List<Map<String, dynamic>> flushLogs() => [];

  @override
  List<Map<String, dynamic>> peekLogs() => [];

  @override
  Map<String, dynamic>? get exportedState => null;

  void emitRender(Map<String, dynamic> tree) => _runtimeConfig.onRender(tree);
}

BoardPanelInstance _panel(String id, {String widgetId = 'weather'}) {
  return BoardPanelInstance(
    id: id,
    type: 'board.widget.custom',
    title: 'Widget',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
    state: {
      'widgetId': widgetId,
      '_storage': {'count': 1},
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetEngineManager manager;
  late WidgetAppRegistry appRegistry;
  late List<JsWidgetEngine> createdEngines;
  late List<FakeJsWidgetEngineBackend> createdBackends;
  late int factoryCalls;

  WidgetManifest manifestFor(String widgetId) => WidgetManifest(
    id: widgetId,
    name: widgetId,
    description: '',
    version: '1.0.0',
    icon: '🔧',
    allowedCommands: const [],
    networkEnabled: true,
    widgetPath: '/widgets/$widgetId',
    isSingleFile: false,
  );

  JsWidgetEngine createEngine(JsRuntimeConfig config) {
    factoryCalls++;
    final backend = FakeJsWidgetEngineBackend(config: config);
    final engine = JsWidgetEngine(config: config.copyWith(backend: backend));
    createdEngines.add(engine);
    createdBackends.add(backend);
    return engine;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRegistry = WidgetAppRegistry.testInstance();
    createdEngines = [];
    createdBackends = [];
    factoryCalls = 0;
    manager = WidgetEngineManager.testInstance(
      appRegistry: appRegistry,
      manifestFinder: (widgetId) async => manifestFor(widgetId),
      jsLoader: (_, __) async => 'console.log("hello")',
      engineFactory: createEngine,
    );
  });

  tearDown(() {
    manager.disposeAll();
  });

  group('WidgetEngineManager', () {
    test('creates and caches engines', () async {
      final engine = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      expect(engine, isNotNull);
      expect(manager.engine('p1'), same(engine));
      expect(manager.activePanelIds, contains('p1'));
      expect(factoryCalls, 1);
      expect(appRegistry.engine('weather'), same(engine));
    });

    test('returns existing engine on getOrCreate', () async {
      final first = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );
      final second = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      expect(second, same(first));
      expect(factoryCalls, 1);
      expect(createdBackends.single.runCount, 1);
    });

    test('detach keeps engine alive', () async {
      final renders = <Map<String, dynamic>>[];
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
        onRenderUI: renders.add,
      );
      final engine = createdEngines.single;
      final backend = createdBackends.single;

      backend.emitRender({'type': 'text', 'value': 'first'});
      manager.detach('p1');
      backend.emitRender({'type': 'text', 'value': 'second'});

      expect(manager.engine('p1'), same(engine));
      expect(renders, [
        {'type': 'text', 'value': 'first'},
      ]);
      expect(manager.tree('p1'), {'type': 'text', 'value': 'second'});
    });

    test('re-attach restores UI callbacks', () async {
      final firstRenders = <Map<String, dynamic>>[];
      final secondRenders = <Map<String, dynamic>>[];

      final first = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
        onRenderUI: firstRenders.add,
      );
      final engine = createdEngines.single;
      final backend = createdBackends.single;
      backend.emitRender({'type': 'text', 'value': 'cached'});

      manager.detach('p1');

      final second = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
        onRenderUI: secondRenders.add,
      );
      backend.emitRender({'type': 'text', 'value': 'live'});

      expect(second, same(first));
      expect(firstRenders, [
        {'type': 'text', 'value': 'cached'},
      ]);
      expect(secondRenders, [
        {'type': 'text', 'value': 'cached'},
        {'type': 'text', 'value': 'live'},
      ]);
    });

    test('remove disposes engine', () async {
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      manager.remove('p1');

      expect(createdBackends.single.disposed, isTrue);
      expect(manager.engine('p1'), isNull);
      expect(appRegistry.engine('weather'), isNull);
    });

    test('disposeAll clears everything', () async {
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );
      await manager.getOrCreate(
        panelId: 'p2',
        widgetId: 'stocks',
        panel: _panel('p2', widgetId: 'stocks'),
      );

      manager.disposeAll();

      expect(manager.activePanelIds, isEmpty);
      expect(createdBackends.every((backend) => backend.disposed), isTrue);
      expect(appRegistry.activeIds(), isEmpty);
    });
  });
}
