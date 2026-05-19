import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';

class FakeJsWidgetEngine extends JsWidgetEngine {
  FakeJsWidgetEngine({
    required super.widgetId,
    required super.appDir,
    required super.onRender,
    required super.onSetTitle,
    required super.onStorageUpdate,
    required super.initialStorage,
    required super.initialTheme,
  });

  bool disposed = false;
  int runCount = 0;
  String? lastJs;

  @override
  Future<void> run(String widgetJs) async {
    runCount++;
    lastJs = widgetJs;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void emitRender(Map<String, dynamic> tree) => onRender(tree);
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
  late List<FakeJsWidgetEngine> createdEngines;
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

  FakeJsWidgetEngine createEngine({
    required String widgetId,
    required String appDir,
    required void Function(Map<String, dynamic> tree) onRender,
    required void Function(String title) onSetTitle,
    required void Function(Map<String, dynamic> storage) onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    required Map<String, dynamic> initialTheme,
  }) {
    factoryCalls++;
    final engine = FakeJsWidgetEngine(
      widgetId: widgetId,
      appDir: appDir,
      onRender: onRender,
      onSetTitle: onSetTitle,
      onStorageUpdate: onStorageUpdate,
      initialStorage: initialStorage,
      initialTheme: initialTheme,
    );
    createdEngines.add(engine);
    return engine;
  }

  setUp(() {
    appRegistry = WidgetAppRegistry.testInstance();
    createdEngines = [];
    factoryCalls = 0;
    manager = WidgetEngineManager.testInstance(
      appRegistry: appRegistry,
      manifestFinder: (widgetId) async => manifestFor(widgetId),
      jsLoader: (_) async => 'console.log("hello")',
      engineFactory:
          ({
            required widgetId,
            required appDir,
            required onRender,
            required onSetTitle,
            required onStorageUpdate,
            required initialStorage,
            required initialTheme,
          }) => createEngine(
            widgetId: widgetId,
            appDir: appDir,
            onRender: onRender,
            onSetTitle: onSetTitle,
            onStorageUpdate: onStorageUpdate,
            initialStorage: initialStorage,
            initialTheme: initialTheme,
          ),
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
      expect(createdEngines.single.runCount, 1);
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

      engine.emitRender({'type': 'text', 'value': 'first'});
      manager.detach('p1');
      engine.emitRender({'type': 'text', 'value': 'second'});

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
      engine.emitRender({'type': 'text', 'value': 'cached'});

      manager.detach('p1');

      final second = await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
        onRenderUI: secondRenders.add,
      );
      engine.emitRender({'type': 'text', 'value': 'live'});

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
      final engine = createdEngines.single;

      manager.remove('p1');

      expect(engine.disposed, isTrue);
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
      expect(createdEngines.every((engine) => engine.disposed), isTrue);
      expect(appRegistry.activeIds(), isEmpty);
    });
  });
}
