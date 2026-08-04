// covers-write: board.webpage (url bar, navigation callbacks, viewport lab)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fakes for the webview_flutter platform layer.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? pageStarted;
  PageEventCallback? pageFinished;
  UrlChangeCallback? urlChange;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    pageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    pageFinished = onPageFinished;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback? onUrlChange) async {
    urlChange = onUrlChange;
  }
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController()
    : super.implementation(const PlatformWebViewControllerCreationParams());

  final List<String> loadRequests = <String>[];
  final List<String> runJavaScriptCalls = <String>[];
  final List<String> runJavaScriptReturningCalls = <String>[];
  final List<String?> userAgents = <String?>[];
  final Map<String, void Function(JavaScriptMessage)> channels =
      <String, void Function(JavaScriptMessage)>{};

  _FakeNavigationDelegate? navigationDelegate;
  String? currentUrlResult;
  String? titleResult;
  Object returningResult = '{"innerWidth":1280}';
  Object? returningError;
  int reloadCount = 0;
  int goBackCount = 0;
  int goForwardCount = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {
    navigationDelegate = delegate as _FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadRequests.add(params.uri.toString());
  }

  @override
  Future<String?> currentUrl() async => currentUrlResult;

  @override
  Future<String?> getTitle() async => titleResult;

  @override
  Future<void> runJavaScript(String javaScript) async {
    runJavaScriptCalls.add(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    runJavaScriptReturningCalls.add(javaScript);
    final error = returningError;
    if (error != null) {
      throw error;
    }
    return returningResult;
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    userAgents.add(userAgent);
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    channels.remove(javaScriptChannelName);
  }

  @override
  Future<void> goBack() async {
    goBackCount++;
  }

  @override
  Future<void> goForward() async {
    goForwardCount++;
  }

  @override
  Future<void> reload() async {
    reloadCount++;
  }
}

class _FakeWebViewPlatform extends WebViewPlatform {
  final List<_FakePlatformWebViewController> createdControllers =
      <_FakePlatformWebViewController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _FakePlatformWebViewController();
    createdControllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);
}

// ─────────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────────

class _Recorder {
  final List<Map<String, dynamic>> stateUpdates = <Map<String, dynamic>>[];
  final List<(double, double)> resizes = <(double, double)>[];
  final List<(String, Map<String, dynamic>, String)> linkedPanels =
      <(String, Map<String, dynamic>, String)>[];
}

BoardPanelInstance _panel({String id = 'p1', Map<String, dynamic>? state}) =>
    BoardPanelInstance(
      id: id,
      type: WebpagePluginBase.kTypeId,
      title: 'Web',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 480),
      state: state ?? <String, dynamic>{'url': '', 'title': '', 'favicon': ''},
    );

Map<String, dynamic> _urlState(String url) =>
    <String, dynamic>{'url': url, 'title': '', 'favicon': ''};

BoardPanelRenderContext _context(_Recorder rec) => BoardPanelRenderContext(
  isSelected: false,
  onFocus: () {},
  onDelete: () {},
  onUpdateState: rec.stateUpdates.add,
  onShowEditor: () {},
  onResize: (w, h) => rec.resizes.add((w, h)),
  onCreateLinkedPanel: (typeId, state, title) async {
    rec.linkedPanels.add((typeId, state, title));
    return 'linked-id';
  },
);

Future<void> _pumpContent(
  WidgetTester tester,
  BoardPanelInstance panel,
  _Recorder rec,
) {
  const plugin = WebpagePlugin();
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => plugin.buildContent(context, panel, _context(rec)),
        ),
      ),
    ),
  );
}

_FakeWebViewPlatform get _platform =>
    WebViewPlatform.instance! as _FakeWebViewPlatform;

/// Registers [fake] as the already-existing controller for panel `p1`.
void _registerExisting(_FakePlatformWebViewController fake) {
  WebViewManager.instance.register('p1', WebViewController.fromPlatform(fake));
}

/// Pumps the panel content with an existing controller and flushes the async
/// controller configuration (channels, state sync).
Future<void> _pumpWithExisting(
  WidgetTester tester,
  _FakePlatformWebViewController fake,
  _Recorder rec,
) async {
  _registerExisting(fake);
  await _pumpContent(tester, _panel(state: _urlState('https://a.example')), rec);
  await tester.pump();
  await tester.pump();
}

/// Enlarges the test surface so the tall Viewport Lab dialog fits without
/// RenderFlex overflow.
void _useBigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openViewportLab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.science_outlined));
  await tester.pumpAndSettle();
  expect(find.text('Viewport Lab'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zoomChannel = MethodChannel('yoloit/webview_zoom');
  final zoomCalls = <MethodCall>[];

  setUp(() {
    WebViewPlatform.instance = _FakeWebViewPlatform();
    zoomCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(zoomChannel, (call) async {
          zoomCalls.add(call);
          return 2;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(zoomChannel, null);
    WebViewManager.instance.disposeAll();
    WebpagePluginBase.controllers.clear();
    WebpagePluginBase.pendingCssZoom.clear();
    WebpagePluginBase.viewportTargets.clear();
    for (final notifier in WebpagePluginBase.pageLoading.values) {
      notifier.dispose();
    }
    WebpagePluginBase.pageLoading.clear();
  });

  group('WebpagePlugin url bar', () {
    testWidgets('shows placeholder when no url is set', (tester) async {
      final rec = _Recorder();
      await _pumpContent(tester, _panel(), rec);
      await tester.pump();

      expect(find.text('Enter a URL above'), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('commit normalizes url, updates state and loads page', (
      tester,
    ) async {
      final rec = _Recorder();
      await _pumpContent(tester, _panel(), rec);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();

      expect(rec.stateUpdates.last['url'], 'https://example.com');
      expect(rec.stateUpdates.last['title'], 'example.com');
      final controller = _platform.createdControllers.single;
      expect(controller.loadRequests, <String>['https://example.com']);

      // Second commit reuses the controller and reloads via loadRequest.
      await tester.enterText(find.byType(TextField), 'https://other.dev/path');
      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(controller.loadRequests, <String>[
        'https://example.com',
        'https://other.dev/path',
      ]);
      expect(rec.stateUpdates.last['url'], 'https://other.dev/path');
      expect(rec.stateUpdates.last['title'], 'other.dev');
    });

    testWidgets('panel url change initializes then reloads controller', (
      tester,
    ) async {
      final rec = _Recorder();
      await _pumpContent(tester, _panel(), rec);
      await tester.pump();

      // didUpdateWidget with no controller yet -> full init.
      await _pumpContent(tester, _panel(state: _urlState('https://a.example')), rec);
      await tester.pump();
      await tester.pump();

      final controller = _platform.createdControllers.single;
      expect(controller.loadRequests, <String>['https://a.example']);
      expect(
        find.widgetWithText(TextField, 'https://a.example'),
        findsOneWidget,
      );

      // didUpdateWidget with an existing controller -> loadRequest only.
      await _pumpContent(tester, _panel(state: _urlState('https://b.example')), rec);
      await tester.pump();

      expect(controller.loadRequests, <String>[
        'https://a.example',
        'https://b.example',
      ]);
    });

    testWidgets('nav buttons call through to the controller', (tester) async {
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(fake.goBackCount, 1);
      expect(fake.goForwardCount, 1);
      expect(fake.reloadCount, 1);
    });
  });

  group('WebpagePlugin controller lifecycle', () {
    testWidgets('reuses registered controller and syncs live url and title', (
      tester,
    ) async {
      final fake =
          _FakePlatformWebViewController()
            ..currentUrlResult = 'https://live.example/page'
            ..titleResult = 'Live Title';
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      // Existing controller path does not issue a fresh loadRequest.
      expect(fake.loadRequests, isEmpty);
      expect(rec.stateUpdates, isNotEmpty);
      expect(rec.stateUpdates.last['url'], 'https://live.example/page');
      expect(rec.stateUpdates.last['title'], 'Live Title');
      expect(
        find.widgetWithText(TextField, 'https://live.example/page'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to hostname when live title is empty', (
      tester,
    ) async {
      final fake =
          _FakePlatformWebViewController()
            ..currentUrlResult = 'https://live.example/page'
            ..titleResult = '  ';
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      expect(rec.stateUpdates.last['title'], 'live.example');
    });

    testWidgets('no state sync when live url is unavailable', (tester) async {
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      expect(rec.stateUpdates, isEmpty);
    });

    testWidgets('navigation callbacks drive loading state and url updates', (
      tester,
    ) async {
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      final delegate = fake.navigationDelegate!;
      final loading = WebpagePluginBase.pageLoading['p1']!;

      delegate.pageStarted!('https://a.example');
      expect(loading.value, isTrue);

      delegate.pageFinished!('https://a.example');
      expect(
        fake.runJavaScriptCalls.any((js) => js.contains('YoloNewTab')),
        isTrue,
      );
      expect(
        zoomCalls.any((call) => call.method == 'setFixedViewportWidth'),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(loading.value, isFalse);

      delegate.urlChange!(const UrlChange(url: 'https://next.example/a'));
      await tester.pump();
      expect(rec.stateUpdates.last['url'], 'https://next.example/a');
      expect(rec.stateUpdates.last['title'], 'next.example');

      // Same url and empty url are ignored.
      final updateCount = rec.stateUpdates.length;
      delegate.urlChange!(const UrlChange(url: 'https://next.example/a'));
      delegate.urlChange!(const UrlChange(url: null));
      await tester.pump();
      expect(rec.stateUpdates.length, updateCount);
    });

    testWidgets('YoloNewTab channel creates a linked panel', (tester) async {
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      final channel = fake.channels['YoloNewTab']!;

      channel(const JavaScriptMessage(message: ''));
      expect(rec.linkedPanels, isEmpty);

      channel(const JavaScriptMessage(message: 'https://tab.example/x'));
      final (typeId, state, title) = rec.linkedPanels.single;
      expect(typeId, WebpagePluginBase.kTypeId);
      expect(state['url'], 'https://tab.example/x');
      expect(state['title'], 'tab.example');
      expect(title, 'tab.example');
    });
  });

  group('WebpagePlugin viewport presets', () {
    testWidgets('mobile and fill presets resize panel and refresh page', (
      tester,
    ) async {
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile  375 × 667'));
      await tester.pumpAndSettle();

      expect(rec.resizes, <(double, double)>[(375.0, 748.0)]);
      expect(WebpagePluginBase.viewportTargets['p1'], 375.0);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fill Screen'));
      await tester.pumpAndSettle();

      // Default test surface is 800x600: w = 720 -> clamped to 800,
      // h = 510 -> clamped to 600, viewport target clamped to 1280.
      expect(rec.resizes.last, (800.0, 600.0));
      expect(WebpagePluginBase.viewportTargets['p1'], 1280.0);

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        fake.runJavaScriptCalls.any(
          (js) => js.contains("dispatchEvent(new Event('resize'))"),
        ),
        isTrue,
      );
    });
  });

  group('Viewport Lab', () {
    testWidgets('apply injects combined css overrides with defaults', (
      tester,
    ) async {
      _useBigSurface(tester);
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(fake.userAgents.single, contains('Chrome/124.0.0.0'));
      final js = fake.runJavaScriptReturningCalls.single;
      expect(js, contains("document.documentElement.style.zoom='0.5';"));
      expect(js, contains("document.body.style.transform='';"));
      expect(js, contains("document.body.style.minWidth='';"));
      expect(js, contains('get:undefined'));
      expect(js, contains("window.__yoloitYtPlayerW=parseInt('1242');"));
      expect(js, contains("window.__yoloitYtPlayerH=parseInt('699');"));
      expect(find.textContaining('"innerWidth":1280'), findsOneWidget);
    });

    testWidgets('apply honors toggled options', (tester) async {
      _useBigSurface(tester);
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      // A off (reset UA), B off (clear zoom), C/D/E on, F off.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.tap(find.byType(Checkbox).at(4));
      await tester.tap(find.byType(Checkbox).at(5));
      await tester.pump();

      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(fake.userAgents.single, isNull);
      final js = fake.runJavaScriptReturningCalls.single;
      expect(js, contains("document.documentElement.style.zoom='';"));
      expect(js, contains("b.style.transform='scale(0.5)';"));
      expect(js, contains("document.body.style.minWidth='1280px';"));
      expect(js, contains("var iw=parseInt('1278');"));
      expect(js, contains('yoloit-yt-player-fix')); // removal snippet
    });

    testWidgets('apply surfaces javascript errors', (tester) async {
      _useBigSurface(tester);
      final fake =
          _FakePlatformWebViewController()
            ..returningError = StateError('boom');
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('apply and reload installs init script with defaults', (
      tester,
    ) async {
      _useBigSurface(tester);
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      await tester.tap(find.text('Apply (Reload)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(fake.userAgents.single, contains('Chrome/124.0.0.0'));
      final install =
          zoomCalls.singleWhere((call) => call.method == 'installInitScript');
      final installArgs = install.arguments as Map<Object?, Object?>;
      final script = installArgs['script']! as String;
      expect(script, contains('applyZoom'));
      expect(script, contains('installYtFix'));
      expect(script, isNot(contains('iw = 1278')));
      expect(installArgs['reload'], isTrue);
      expect(find.textContaining('Installed on 2 WKWebView(s)'), findsOneWidget);
      expect(fake.runJavaScriptReturningCalls.last, contains('JSON.stringify'));
    });

    testWidgets('apply and reload honors toggled options', (tester) async {
      _useBigSurface(tester);
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      // A off, B off (no init zoom), E on (custom innerWidth), F off.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(4));
      await tester.tap(find.byType(Checkbox).at(5));
      await tester.pump();

      await tester.tap(find.text('Apply (Reload)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(fake.userAgents.single, isNull);
      final install =
          zoomCalls.singleWhere((call) => call.method == 'installInitScript');
      final script =
          (install.arguments as Map<Object?, Object?>)['script']! as String;
      expect(script, contains('iw = 1278;'));
      expect(script, isNot(contains('applyZoom')));
      expect(script, isNot(contains('installYtFix')));
    });

    testWidgets('reset clears all overrides', (tester) async {
      _useBigSurface(tester);
      final fake = _FakePlatformWebViewController();
      final rec = _Recorder();
      await _pumpWithExisting(tester, fake, rec);
      await _openViewportLab(tester);

      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fake.userAgents.single, isNull);
      expect(
        zoomCalls.any((call) => call.method == 'clearInitScripts'),
        isTrue,
      );
      expect(
        fake.runJavaScriptCalls.any((js) => js.contains('yoloit-yt-player-fix')),
        isTrue,
      );
      expect(find.text('All CSS overrides reset.'), findsOneWidget);
    });
  });
}
