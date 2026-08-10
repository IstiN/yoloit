// covers: board.widget.custom (shared content widgets)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_content.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

BoardPanelRenderContext _dummyContext({
  ValueChanged<Map<String, dynamic>>? onUpdateState,
  Future<String?> Function(String typeId, Map<String, dynamic> state, String title)?
  onCreateLinkedPanel,
}) => BoardPanelRenderContext(
  isSelected: false,
  onFocus: () {},
  onDelete: () {},
  onUpdateState: onUpdateState ?? (_) {},
  onShowEditor: () {},
  onCreateLinkedPanel: onCreateLinkedPanel,
);

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: CustomWidgetPluginBase.kTypeId,
      title: 'Widget',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
      state: state,
    );

class _FakeBackend extends JsWidgetEngineBackend {
  _FakeBackend({required this.onRender, this.label});

  final void Function(Map<String, dynamic> tree) onRender;
  final String? label;

  @override
  Future<void> init() async {}

  @override
  Future<void> run(
    String widgetJs, {
    String? hostBootstrapJs,
    Map<String, dynamic> initialTheme = const {},
  }) async {
    final id = label;
    onRender({
      'type': 'text',
      'data': id == null ? 'Hello from widget' : 'widget:$id',
    });
  }

  @override
  Future<void> callEvent(String actionId, [Map<String, dynamic>? payload]) async {}

  @override
  void updateTheme(Map<String, dynamic> colors) {}

  @override
  Future<void> dispose() async {}

  @override
  List<Map<String, dynamic>> flushLogs() => [];

  @override
  List<Map<String, dynamic>> peekLogs() => [];

  @override
  Map<String, dynamic>? get exportedState => null;
}

WidgetEngineManager _fakeEngineManager() => WidgetEngineManager.testInstance(
  engineFactory:
      (config) => JsWidgetEngine(
        config: config.copyWith(
          backend: _FakeBackend(
            onRender: config.onRender,
            label: config.widgetId,
          ),
        ),
      ),
  manifestFinder:
      (id) async => WidgetManifest(
        id: id,
        name: 'Test',
        description: '',
        version: '1.0.0',
        icon: '🔧',
        allowedCommands: const [],
        networkEnabled: true,
        widgetPath: 'widgets/$id',
        isSingleFile: false,
      ),
  jsLoader: (manifest, reader) async => '// noop',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('QuickSizeButton', () {
    testWidgets('opens menu and calls onResize with selected size', (
      tester,
    ) async {
      double? selectedW;
      double? selectedH;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickSizeButton(
              onResize: (w, h) {
                selectedW = w;
                selectedH = h;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(QuickSizeButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile (390×844)'));
      await tester.pumpAndSettle();

      expect(selectedW, 390);
      expect(selectedH, 844);
    });
  });

  group('EnvGearButton', () {
    testWidgets('opens env dialog and saves custom variables', (tester) async {
      List<String>? savedGroups;
      Map<String, dynamic>? savedVars;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvGearButton(
              panel: _panel(),
              onUpdate: (groups, vars) {
                savedGroups = groups;
                savedVars = vars;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EnvGearButton));
      await tester.pumpAndSettle();

      expect(find.text('Environment Variables'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final keyField = find.widgetWithText(TextField, 'KEY').first;
      final valueField = find.widgetWithText(TextField, 'value').first;
      await tester.enterText(keyField, 'API_URL');
      await tester.enterText(valueField, 'https://example.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedGroups, isEmpty);
      expect(savedVars, {'API_URL': 'https://example.com'});
    });

    testWidgets('clear all resets custom variables', (tester) async {
      List<String>? savedGroups;
      Map<String, dynamic>? savedVars;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvGearButton(
              panel: _panel(
                state: {
                  '_customEnvVars': {'OLD': 'value'},
                },
              ),
              onUpdate: (groups, vars) {
                savedGroups = groups;
                savedVars = vars;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EnvGearButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedGroups, isEmpty);
      expect(savedVars, isEmpty);
    });
  });

  group('CustomWidgetContent', () {
    testWidgets('empty widgetId shows no-widgets message when list empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomWidgetContent(
              panel: _panel(),
              renderContext: _dummyContext(),
              loadWidgets: () async => const <WidgetManifest>[],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('No widgets installed.'), findsOneWidget);
      expect(find.text('Run: yoloit widget:list'), findsOneWidget);
    });

    testWidgets('empty widgetId shows picker and updates state on tap', (
      tester,
    ) async {
      Map<String, dynamic>? updatedState;
      const manifest = WidgetManifest(
        id: 'weather',
        name: 'Weather',
        description: 'A weather widget',
        version: '1.0.0',
        icon: '🌤️',
        allowedCommands: [],
        networkEnabled: true,
        widgetPath: 'widgets/weather',
        isSingleFile: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomWidgetContent(
              panel: _panel(),
              renderContext: _dummyContext(
                onUpdateState: (state) => updatedState = state,
              ),
              loadWidgets: () async => [manifest],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('A weather widget'), findsOneWidget);

      await tester.tap(find.text('Weather'));
      await tester.pump();

      expect(updatedState?['widgetId'], 'weather');
    });

    testWidgets('non-empty widgetId renders tree from engine manager', (
      tester,
    ) async {
      final engineManagerWithRender = WidgetEngineManager.testInstance(
        engineFactory:
            (config) => JsWidgetEngine(
              config: config.copyWith(
                backend: _FakeBackend(onRender: config.onRender),
              ),
            ),
        manifestFinder: (id) async => WidgetManifest(
          id: id,
          name: 'Test',
          description: '',
          version: '1.0.0',
          icon: '🔧',
          allowedCommands: const [],
          networkEnabled: true,
          widgetPath: 'widgets/$id',
          isSingleFile: false,
        ),
        jsLoader: (manifest, reader) async => '// noop',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomWidgetContent(
              panel: _panel(state: {'widgetId': 'demo'}),
              renderContext: _dummyContext(),
              engineManager: engineManagerWithRender,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hello from widget'), findsOneWidget);
    });

    testWidgets('didUpdateWidget reloads engine when widgetId changes', (
      tester,
    ) async {
      final engineManager = _fakeEngineManager();

      Widget build(String widgetId) => MaterialApp(
        home: Scaffold(
          body: CustomWidgetContent(
            panel: _panel(state: {'widgetId': widgetId}),
            renderContext: _dummyContext(),
            engineManager: engineManager,
          ),
        ),
      );

      await tester.pumpWidget(build('one'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('widget:one'), findsOneWidget);

      await tester.pumpWidget(build('two'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('widget:two'), findsOneWidget);
      expect(find.text('widget:one'), findsNothing);
    });

    testWidgets('didUpdateWidget reapplies env vars without engine reload', (
      tester,
    ) async {
      final engineManager = _fakeEngineManager();

      Widget build(Map<String, dynamic> state) => MaterialApp(
        home: Scaffold(
          body: CustomWidgetContent(
            panel: _panel(state: state),
            renderContext: _dummyContext(),
            engineManager: engineManager,
          ),
        ),
      );

      await tester.pumpWidget(
        build({
          'widgetId': 'one',
          '_customEnvVars': {'A': '1'},
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('widget:one'), findsOneWidget);
      final engine = engineManager.engine('p1');

      // Same widgetId, changed env state: env vars re-applied in place.
      await tester.pumpWidget(
        build({
          'widgetId': 'one',
          '_customEnvVars': {'A': '2'},
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('widget:one'), findsOneWidget);
      expect(engineManager.engine('p1'), same(engine));
    });
  });
}
