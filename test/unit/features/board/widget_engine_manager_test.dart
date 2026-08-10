// covers-write: board.widget.custom
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

class FakeJsWidgetEngineBackend extends JsWidgetEngineBackend {
  FakeJsWidgetEngineBackend({required JsRuntimeConfig config})
    : _runtimeConfig = config;

  final JsRuntimeConfig _runtimeConfig;

  bool disposed = false;
  int runCount = 0;
  String? lastJs;

  /// Values settled by host handlers via the engine resolver.
  final Map<String, dynamic> resolved = <String, dynamic>{};

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
    _runtimeConfig.onResolveReady?.call((id, value) => resolved[id] = value);
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
  late List<JsRuntimeConfig> createdConfigs;
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
    createdConfigs.add(config);
    return engine;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRegistry = WidgetAppRegistry.testInstance();
    createdEngines = [];
    createdBackends = [];
    createdConfigs = [];
    factoryCalls = 0;
    manager = WidgetEngineManager.testInstance(
      appRegistry: appRegistry,
      manifestFinder: (widgetId) async => manifestFor(widgetId),
      jsLoader: (_, _) async => 'console.log("hello")',
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

  group('exec handler', () {
    setUp(() async {
      await WidgetPermissionsService.instance.setAllowed('exec', true);
    });

    tearDown(() async {
      WidgetEngineManager.debugYoloitBinPath = null;
      await WidgetPermissionsService.instance.setAllowed('exec', true);
    });

    test('resolves error when exec permission is disabled', () async {
      await WidgetPermissionsService.instance.setAllowed('exec', false);
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      await createdConfigs.single.execHandler!('e1', 'yoloit board:list');

      expect(createdBackends.single.resolved['e1'], {
        '__error': 'exec is disabled in Settings → Apps & Widgets',
      });
    });

    test('rejects non-yoloit commands', () async {
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      await createdConfigs.single.execHandler!('e2', 'rm -rf /');

      expect(createdBackends.single.resolved['e2'], {
        '__error': 'Only yoloit commands are allowed',
      });
    });

    test('runs yoloit binary and maps stdout/stderr/exitCode', () async {
      final dir = Directory.systemTemp.createTempSync('wem_exec_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final script = File('${dir.path}/fake_yoloit');
      script.writeAsStringSync(
        '#!/bin/sh\necho "out:\$1:\$FOO"\necho "some-err" >&2\nexit 3\n',
      );
      Process.runSync('chmod', ['+x', script.path]);
      WidgetEngineManager.debugYoloitBinPath = script.path;

      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );
      manager.applyEnvVars('p1', {'FOO': 'bar'});

      await createdConfigs.single.execHandler!('e3', 'yoloit hello world');

      final result = createdBackends.single.resolved['e3'] as Map;
      expect(result['stdout'], 'out:hello:bar\n');
      expect(result['stderr'], 'some-err\n');
      expect(result['exitCode'], 3);
    });

    test('resolves __error when the binary cannot be started', () async {
      WidgetEngineManager.debugYoloitBinPath = '/nonexistent/yoloit-bin';
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      await createdConfigs.single.execHandler!('e4', 'yoloit board:list');

      final result = createdBackends.single.resolved['e4'] as Map;
      expect(result['__error'], isNotNull);
      expect(result.containsKey('exitCode'), isFalse);
    });
  });

  group('loadAsset handler', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wem_assets_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    WidgetEngineManager managerFor(WidgetManifest manifest) {
      final m = WidgetEngineManager.testInstance(
        appRegistry: WidgetAppRegistry.testInstance(),
        manifestFinder: (_) async => manifest,
        jsLoader: (_, _) async => '// js',
        engineFactory: createEngine,
      );
      addTearDown(m.disposeAll);
      return m;
    }

    WidgetManifest manifestIn(String path, {bool singleFile = false}) =>
        WidgetManifest(
          id: 'assets',
          name: 'assets',
          description: '',
          version: '1.0.0',
          icon: '🔧',
          allowedCommands: const [],
          networkEnabled: true,
          widgetPath: path,
          isSingleFile: singleFile,
        );

    test('resolves file contents for existing assets', () async {
      File('${tempDir.path}/hello.txt').writeAsStringSync('asset-body');
      final m = managerFor(manifestIn(tempDir.path));
      await m.getOrCreate(panelId: 'p1', widgetId: 'assets', panel: _panel('p1'));

      await createdConfigs.last.loadAssetHandler!('a1', 'hello.txt');

      expect(createdBackends.last.resolved['a1'], 'asset-body');
    });

    test('resolves nested asset paths', () async {
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/sub/data.json').writeAsStringSync('{"ok":true}');
      final m = managerFor(manifestIn(tempDir.path));
      await m.getOrCreate(panelId: 'p1', widgetId: 'assets', panel: _panel('p1'));

      await createdConfigs.last.loadAssetHandler!('a2', 'sub/data.json');

      expect(createdBackends.last.resolved['a2'], '{"ok":true}');
    });

    test('resolves null for missing files', () async {
      final m = managerFor(manifestIn(tempDir.path));
      await m.getOrCreate(panelId: 'p1', widgetId: 'assets', panel: _panel('p1'));

      await createdConfigs.last.loadAssetHandler!('a3', 'missing.txt');

      expect(createdBackends.last.resolved.containsKey('a3'), isTrue);
      expect(createdBackends.last.resolved['a3'], isNull);
    });

    test('resolves null when the app directory is empty', () async {
      final m = managerFor(manifestIn('', singleFile: true));
      await m.getOrCreate(panelId: 'p1', widgetId: 'assets', panel: _panel('p1'));

      await createdConfigs.last.loadAssetHandler!('a4', 'anything.txt');

      expect(createdBackends.last.resolved.containsKey('a4'), isTrue);
      expect(createdBackends.last.resolved['a4'], isNull);
    });
  });

  group('panel title/storage updates', () {
    late _MockBoardCubit cubit;

    setUp(() {
      cubit = _MockBoardCubit();
      registerFallbackValue((BoardPanelInstance panel) => panel);
    });

    void stubBoards(List<BoardDocument> boards) {
      when(() => cubit.state).thenReturn(BoardState(boards: boards));
    }

    Completer<void> stubUpdatePanel() {
      final done = Completer<void>();
      when(
        () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
      ).thenAnswer((_) async => done.complete());
      return done;
    }

    BoardDocument boardWith(BoardPanelInstance panel) =>
        BoardDocument(id: 'b1', name: 'Board', panels: [panel]);

    test('onSetTitle locates the panel and updates its title', () async {
      stubBoards([boardWith(_panel('p1'))]);
      final done = stubUpdatePanel();
      manager.setCubit(cubit);
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      createdConfigs.single.onSetTitle('New title');
      await done.future.timeout(const Duration(seconds: 5));

      final captured =
          verify(
                () => cubit.updatePanel('p1', captureAny(), boardId: 'b1'),
              ).captured
              .single
              as BoardPanelInstance Function(BoardPanelInstance);
      final updated = captured(_panel('p1'));
      expect(updated.title, 'New title');
      expect(updated.state['_title'], 'New title');
    });

    test('onStorageUpdate locates the panel and merges storage', () async {
      stubBoards([boardWith(_panel('p1'))]);
      final done = stubUpdatePanel();
      manager.setCubit(cubit);
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      createdConfigs.single.onStorageUpdate({'total': 42});
      await done.future.timeout(const Duration(seconds: 5));

      final captured =
          verify(
                () => cubit.updatePanel('p1', captureAny(), boardId: 'b1'),
              ).captured
              .single
              as BoardPanelInstance Function(BoardPanelInstance);
      final updated = captured(_panel('p1'));
      expect(updated.state['_storage'], {'total': 42});
      // Unrelated state keys are preserved.
      expect(updated.state['widgetId'], 'weather');
    });

    test('ignores updates for panels that are not on any board', () async {
      stubBoards(const []);
      manager.setCubit(cubit);
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      createdConfigs.single.onSetTitle('Ignored');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verifyNever(
        () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
      );
    });

    test('ignores updates when no cubit is attached', () async {
      await manager.getOrCreate(
        panelId: 'p1',
        widgetId: 'weather',
        panel: _panel('p1'),
      );

      // No setCubit call: title/storage updates must be no-ops.
      createdConfigs.single.onSetTitle('No cubit');
      createdConfigs.single.onStorageUpdate({'a': 1});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(manager.engine('p1'), isNotNull);
    });
  });
}
