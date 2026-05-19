import 'dart:async';

import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

typedef WidgetEngineFactory =
    JsWidgetEngine Function({
      required String widgetId,
      required String appDir,
      required void Function(Map<String, dynamic> tree) onRender,
      required void Function(String title) onSetTitle,
      required void Function(Map<String, dynamic> storage) onStorageUpdate,
      required Map<String, dynamic> initialStorage,
      required Map<String, dynamic> initialTheme,
    });

typedef WidgetManifestFinder =
    Future<WidgetManifest?> Function(String widgetId);
typedef WidgetJsLoader = Future<String?> Function(WidgetManifest manifest);

class WidgetEngineManager {
  WidgetEngineManager._({
    WidgetEngineFactory? engineFactory,
    WidgetManifestFinder? manifestFinder,
    WidgetJsLoader? jsLoader,
    WidgetAppRegistry? appRegistry,
  }) : _engineFactory = engineFactory,
       _manifestFinder = manifestFinder,
       _jsLoader = jsLoader,
       _appRegistry = appRegistry ?? WidgetAppRegistry.instance;

  static final instance = WidgetEngineManager._();
  factory WidgetEngineManager.testInstance({
    WidgetEngineFactory? engineFactory,
    WidgetManifestFinder? manifestFinder,
    WidgetJsLoader? jsLoader,
    WidgetAppRegistry? appRegistry,
  }) => WidgetEngineManager._(
    engineFactory: engineFactory,
    manifestFinder: manifestFinder,
    jsLoader: jsLoader,
    appRegistry: appRegistry,
  );

  final WidgetEngineFactory? _engineFactory;
  final WidgetManifestFinder? _manifestFinder;
  final WidgetJsLoader? _jsLoader;
  final WidgetAppRegistry _appRegistry;

  BoardCubit? _cubit;
  void setCubit(BoardCubit cubit) => _cubit = cubit;

  final Map<String, _WidgetEngineEntry> _engines = {};

  Future<JsWidgetEngine?> getOrCreate({
    required String panelId,
    required String widgetId,
    required BoardPanelInstance panel,
    Map<String, dynamic> initialTheme = const {},
    void Function(Map<String, dynamic> tree)? onRenderUI,
  }) async {
    if (widgetId.trim().isEmpty) return null;

    final existing = _engines[panelId];
    if (existing != null) {
      if (existing.widgetId != widgetId) {
        remove(panelId);
      } else {
        existing.onRenderUI = onRenderUI;
        existing.engine.updateTheme(initialTheme);
        final tree = existing.uiTree;
        if (tree != null) {
          onRenderUI?.call(Map<String, dynamic>.from(tree));
        }
        return existing.engine;
      }
    }

    final manifest = await _findManifest(widgetId);
    if (manifest == null) {
      throw _WidgetEngineLoadError('Widget "$widgetId" not found');
    }

    final js = await _readJs(manifest);
    if (js == null) {
      throw _WidgetEngineLoadError('widget.js missing for "$widgetId"');
    }

    late final _WidgetEngineEntry entry;
    final engine = _createEngine(
      widgetId: widgetId,
      appDir: manifest.appDir,
      initialStorage: Map<String, dynamic>.from(
        panel.state['_storage'] as Map? ?? const {},
      ),
      initialTheme: Map<String, dynamic>.from(initialTheme),
      onRender: (tree) {
        entry.uiTree = Map<String, dynamic>.from(tree);
        _appRegistry.updateTree(widgetId, tree);
        entry.onRenderUI?.call(Map<String, dynamic>.from(tree));
      },
      onSetTitle: (title) => _updatePanelTitle(panelId, title),
      onStorageUpdate: (storage) => _updatePanelStorage(panelId, storage),
    );

    entry = _WidgetEngineEntry(
      engine: engine,
      widgetId: widgetId,
      uiTree: null,
      onRenderUI: onRenderUI,
    );
    _engines[panelId] = entry;

    try {
      await engine.run(js);
      _appRegistry.register(widgetId, engine, entry.uiTree);
      return engine;
    } catch (_) {
      _engines.remove(panelId);
      _appRegistry.unregister(widgetId, engine: engine);
      unawaited(engine.dispose());
      rethrow;
    }
  }

  void detach(String panelId) {
    final entry = _engines[panelId];
    if (entry == null) return;
    entry.onRenderUI = null;
  }

  JsWidgetEngine? engine(String panelId) => _engines[panelId]?.engine;

  Map<String, dynamic>? tree(String panelId) {
    final uiTree = _engines[panelId]?.uiTree;
    return uiTree == null ? null : Map<String, dynamic>.from(uiTree);
  }

  List<String> get activePanelIds => _engines.keys.toList();

  void remove(String panelId) {
    final entry = _engines.remove(panelId);
    if (entry == null) return;
    _appRegistry.unregister(entry.widgetId, engine: entry.engine);
    unawaited(entry.engine.dispose());
  }

  void disposeAll() {
    for (final entry in _engines.values) {
      _appRegistry.unregister(entry.widgetId, engine: entry.engine);
      unawaited(entry.engine.dispose());
    }
    _engines.clear();
  }

  JsWidgetEngine _createEngine({
    required String widgetId,
    required String appDir,
    required void Function(Map<String, dynamic> tree) onRender,
    required void Function(String title) onSetTitle,
    required void Function(Map<String, dynamic> storage) onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    required Map<String, dynamic> initialTheme,
  }) {
    final factory = _engineFactory;
    if (factory != null) {
      return factory(
        widgetId: widgetId,
        appDir: appDir,
        onRender: onRender,
        onSetTitle: onSetTitle,
        onStorageUpdate: onStorageUpdate,
        initialStorage: initialStorage,
        initialTheme: initialTheme,
      );
    }
    return JsWidgetEngine(
      widgetId: widgetId,
      appDir: appDir,
      onRender: onRender,
      onSetTitle: onSetTitle,
      onStorageUpdate: onStorageUpdate,
      initialStorage: initialStorage,
      initialTheme: initialTheme,
    );
  }

  Future<WidgetManifest?> _findManifest(String widgetId) {
    final finder = _manifestFinder;
    if (finder != null) return finder(widgetId);
    return WidgetRegistryService.instance.find(widgetId);
  }

  Future<String?> _readJs(WidgetManifest manifest) {
    final loader = _jsLoader;
    if (loader != null) return loader(manifest);
    return manifest.readJs();
  }

  Future<void> _updatePanelTitle(String panelId, String title) async {
    final location = _locatePanel(panelId);
    final cubit = _cubit;
    if (location == null || cubit == null) return;
    await cubit.updatePanel(
      panelId,
      (panel) => panel.copyWith(
        title: title,
        state: {...panel.state, '_title': title},
      ),
      boardId: location.boardId,
    );
  }

  Future<void> _updatePanelStorage(
    String panelId,
    Map<String, dynamic> storage,
  ) async {
    final location = _locatePanel(panelId);
    final cubit = _cubit;
    if (location == null || cubit == null) return;
    await cubit.updatePanel(
      panelId,
      (panel) => panel.copyWith(
        state: {...panel.state, '_storage': Map<String, dynamic>.from(storage)},
      ),
      boardId: location.boardId,
    );
  }

  _PanelLocation? _locatePanel(String panelId) {
    final cubit = _cubit;
    if (cubit == null) return null;
    for (final board in cubit.state.boards) {
      for (final panel in board.panels) {
        if (panel.id == panelId) {
          return _PanelLocation(boardId: board.id);
        }
      }
    }
    return null;
  }
}

class _WidgetEngineEntry {
  _WidgetEngineEntry({
    required this.engine,
    required this.widgetId,
    required this.uiTree,
    required this.onRenderUI,
  });

  final JsWidgetEngine engine;
  final String widgetId;
  Map<String, dynamic>? uiTree;
  void Function(Map<String, dynamic> tree)? onRenderUI;
}

class _PanelLocation {
  const _PanelLocation({required this.boardId});

  final String boardId;
}

class _WidgetEngineLoadError implements Exception {
  const _WidgetEngineLoadError(this.message);

  final String message;

  @override
  String toString() => message;
}
