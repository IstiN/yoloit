import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/widgets/js_widget_3d_dispatcher_host.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_file_reader.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

typedef WidgetEngineFactory = JsWidgetEngine Function(JsRuntimeConfig config);

typedef WidgetManifestFinder =
    Future<WidgetManifest?> Function(String widgetId);
typedef WidgetJsLoader =
    Future<String?> Function(WidgetManifest manifest, WidgetFileReader reader);

class WidgetEngineManager {
  WidgetEngineManager._({
    WidgetEngineFactory? engineFactory,
    WidgetManifestFinder? manifestFinder,
    WidgetJsLoader? jsLoader,
    WidgetAppRegistry? appRegistry,
    WidgetFileReader? reader,
  }) : _engineFactory = engineFactory,
       _manifestFinder = manifestFinder,
       _jsLoader = jsLoader,
       _appRegistry = appRegistry ?? WidgetAppRegistry.instance,
       _reader = reader ?? defaultWidgetFileReader;

  static final instance = WidgetEngineManager._();
  factory WidgetEngineManager.testInstance({
    WidgetEngineFactory? engineFactory,
    WidgetManifestFinder? manifestFinder,
    WidgetJsLoader? jsLoader,
    WidgetAppRegistry? appRegistry,
    WidgetFileReader? reader,
  }) => WidgetEngineManager._(
    engineFactory: engineFactory,
    manifestFinder: manifestFinder,
    jsLoader: jsLoader,
    appRegistry: appRegistry,
    reader: reader,
  );

  final WidgetEngineFactory? _engineFactory;
  final WidgetManifestFinder? _manifestFinder;
  final WidgetJsLoader? _jsLoader;
  final WidgetAppRegistry _appRegistry;
  final WidgetFileReader _reader;

  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  BoardCubit? _cubit;
  void setCubit(BoardCubit cubit) => _cubit = cubit;

  final Map<String, _WidgetEngineEntry> _engines = {};
  final Map<String, Map<String, String>> _envVars = {};

  Future<JsWidgetEngine?> getOrCreate({
    required String panelId,
    required String widgetId,
    required BoardPanelInstance panel,
    Map<String, dynamic> initialTheme = const {},
    void Function(Map<String, dynamic> tree)? onRenderUI,
  }) async {
    if (widgetId.trim().isEmpty) return null;
    await WidgetPermissionsService.instance.load();

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
    final canonicalId = manifest.id;

    final js = await _readJs(manifest);
    if (js == null) {
      throw _WidgetEngineLoadError('widget.js missing for "$widgetId"');
    }

    late final _WidgetEngineEntry entry;
    final engine = _createEngine(
      panelId: panelId,
      widgetId: canonicalId,
      appDir: manifest.appDir,
      initialStorage: Map<String, dynamic>.from(
        panel.state['_storage'] as Map? ?? const {},
      ),
      initialTheme: Map<String, dynamic>.from(initialTheme),
      onRender: (tree) {
        entry.uiTree = Map<String, dynamic>.from(tree);
        _appRegistry.updateTree(canonicalId, tree);
        entry.onRenderUI?.call(Map<String, dynamic>.from(tree));
      },
      onSetTitle: (title) => _updatePanelTitle(panelId, title),
      onStorageUpdate: (storage) => _updatePanelStorage(panelId, storage),
      onResolveReady: (resolve) {},
    );

    entry = _WidgetEngineEntry(
      engine: engine,
      widgetId: canonicalId,
      uiTree: null,
      onRenderUI: onRenderUI,
    );
    _engines[panelId] = entry;

    try {
      await engine.run(js);
      _appRegistry.register(canonicalId, engine, entry.uiTree);
      if (widgetId != canonicalId) {
        _appRegistry.registerAlias(widgetId, canonicalId);
      }
      return engine;
    } catch (_) {
      _engines.remove(panelId);
      _appRegistry.unregister(canonicalId, engine: engine);
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
    _envVars.remove(panelId);
    _appRegistry.unregister(entry.widgetId, engine: entry.engine);
    unawaited(entry.engine.dispose());
  }

  void disposeAll() {
    for (final entry in _engines.values) {
      _appRegistry.unregister(entry.widgetId, engine: entry.engine);
      unawaited(entry.engine.dispose());
    }
    _engines.clear();
    _envVars.clear();
  }

  JsWidgetEngine _createEngine({
    required String panelId,
    required String widgetId,
    required String appDir,
    required void Function(Map<String, dynamic> tree) onRender,
    required void Function(String title) onSetTitle,
    required void Function(Map<String, dynamic> storage) onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    required Map<String, dynamic> initialTheme,
    required void Function(void Function(String id, dynamic value) resolve)
        onResolveReady,
  }) {
    void Function(String id, dynamic value)? resolve;
    onResolveReady((id, value) => resolve?.call(id, value));

    final config = JsRuntimeConfig(
      widgetId: widgetId,
      appDir: appDir,
      initialTheme: initialTheme,
      initialStorage: initialStorage,
      js3dHost: createYoloitJs3dHost(),
      onRender: (tree) {
        debugPrint(
          '[WidgetEngineManager] onRender widgetId=$widgetId '
          'hasScene3d=${_treeHasScene3d(tree)}',
        );
        onRender(tree);
      },
      onSetTitle: onSetTitle,
      onStorageUpdate: onStorageUpdate,
      isPermissionAllowed: (capability) {
        if (capability == 'exec') {
          return WidgetPermissionsService.instance.isAllowed('exec');
        }
        return true;
      },
      fetchHandler: (id, url, method, headers) async {
        if (!WidgetPermissionsService.instance.isAllowed('fetch')) {
          resolve?.call(id, {
            '__error': 'fetch is disabled in Settings → Apps & Widgets',
          });
          return;
        }
        await _handleFetch(resolve, id, url, method, headers);
      },
      secretsGetHandler: (id, key) async {
        final fullKey = '_widget_${widgetId}_$key';
        try {
          final val = await _secureStorage.read(key: fullKey);
          resolve?.call(id, val);
        } catch (_) {
          resolve?.call(id, null);
        }
      },
      secretsSetHandler: (id, key, value) async {
        final fullKey = '_widget_${widgetId}_$key';
        try {
          if (value == null) {
            await _secureStorage.delete(key: fullKey);
          } else {
            await _secureStorage.write(key: fullKey, value: value.toString());
          }
          resolve?.call(id, true);
        } catch (_) {
          resolve?.call(id, false);
        }
      },
      loadAssetHandler: (id, path) async {
        try {
          final dir = appDir;
          if (dir.isEmpty) {
            resolve?.call(id, null);
            return;
          }
          final file = File(
            '$dir${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
          );
          if (await file.exists()) {
            final content = await file.readAsString();
            resolve?.call(id, content);
          } else {
            resolve?.call(id, null);
          }
        } catch (e) {
          debugPrint('[WidgetEngineManager] loadAsset error: $e');
          resolve?.call(id, null);
        }
      },
      execHandler: (id, cmd) async {
        if (!WidgetPermissionsService.instance.isAllowed('exec')) {
          resolve?.call(id, {
            '__error': 'exec is disabled in Settings → Apps & Widgets',
          });
          return;
        }
        if (!cmd.startsWith('yoloit ') && cmd != 'yoloit') {
          resolve?.call(id, {'__error': 'Only yoloit commands are allowed'});
          return;
        }
        try {
          final yoloitBin = '${Platform.environment['HOME']}/.config/yoloit/yoloit';
          final cmdArgs = cmd.substring('yoloit'.length).trim().split(
            RegExp(r'\s+'),
          );
          final env = Map<String, String>.from(Platform.environment)
            ..addAll(_envVars[panelId] ?? const {});
          final result = await Process.run(
            yoloitBin,
            cmdArgs.where((s) => s.isNotEmpty).toList(),
            environment: env,
          ).timeout(const Duration(seconds: 30));
          resolve?.call(id, {
            'stdout': result.stdout.toString(),
            'stderr': result.stderr.toString(),
            'exitCode': result.exitCode,
          });
        } catch (e) {
          resolve?.call(id, {'__error': e.toString()});
        }
      },
      onResolveReady: (resolveFn) {
        resolve = resolveFn;
        onResolveReady(resolveFn);
      },
    );

    final factory = _engineFactory;
    if (factory != null) return factory(config);
    return JsWidgetEngine(config: config);
  }

  Future<void> _handleFetch(
    void Function(String id, dynamic value)? resolve,
    String id,
    String url,
    String method,
    Map<String, String> headers,
  ) async {
    try {
      final client = HttpClient();
      final dartReq = await client.openUrl(method, Uri.parse(url));
      dartReq.headers.set('User-Agent', 'YoLoIT-Widget/1.0');
      dartReq.headers.set('Accept', 'application/json');
      headers.forEach((k, v) => dartReq.headers.set(k, v));
      final res = await dartReq.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(const Utf8Decoder()).join();
      client.close();
      final result = jsonDecode(body);
      resolve?.call(id, result);
    } catch (e) {
      resolve?.call(id, {'__error': e.toString()});
    }
  }

  Future<WidgetManifest?> _findManifest(String widgetId) {
    final finder = _manifestFinder;
    if (finder != null) return finder(widgetId);
    return WidgetRegistryService.instance.find(widgetId);
  }

  Future<String?> _readJs(WidgetManifest manifest) {
    final loader = _jsLoader;
    if (loader != null) return loader(manifest, _reader);
    return manifest.readJs(reader: _reader);
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

  void applyEnvVars(String panelId, Map<String, String> envVars) {
    _envVars[panelId] = {...envVars};
  }

  static bool _treeHasScene3d(Map<String, dynamic> tree) {
    final type = tree['type'] as String?;
    if (type == 'scene3d') return true;
    final children = tree['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, dynamic> && _treeHasScene3d(child)) {
          return true;
        }
      }
    }
    final child = tree['child'];
    if (child is Map<String, dynamic>) {
      return _treeHasScene3d(child);
    }
    return false;
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
