import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';

class _MockPlatformWebViewController extends Mock
    implements PlatformWebViewController {}

class _FakeJavaScriptChannelParams extends Fake
    implements JavaScriptChannelParams {}

class _FakeNavigationDelegateParams extends Fake
    implements PlatformNavigationDelegateCreationParams {}

class _MockPlatformNavigationDelegate extends Mock
    with MockPlatformInterfaceMixin
    implements PlatformNavigationDelegate {}

class _MockWebViewPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements WebViewPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(_FakeJavaScriptChannelParams());
    registerFallbackValue(_FakeNavigationDelegateParams());
    registerFallbackValue(_MockPlatformNavigationDelegate());
    final platform = _MockWebViewPlatform();
    when(
      () => platform.createPlatformNavigationDelegate(any()),
    ).thenReturn(_MockPlatformNavigationDelegate());
    WebViewPlatform.instance = platform;
  });

  group('WebViewManager', () {
    late WebViewManager manager;

    setUp(() {
      manager = WebViewManager.testInstance();
    });

    tearDown(() {
      manager.disposeAll();
      WebpagePluginBase.controllers.clear();
    });

    test('register exposes controller and has panel id', () {
      final controller = _controller();

      manager.register('p1', controller);

      expect(manager.has('p1'), isTrue);
      expect(manager.controller('p1'), same(controller));
      expect(manager.activePanelIds, ['p1']);
      expect(manager.isAttached('p1'), isTrue);
    });

    test('detach keeps entry alive but marks it detached', () {
      manager.registerEntry('p1', WebViewEntry());

      manager.detach('p1');

      expect(manager.has('p1'), isTrue);
      expect(manager.controller('p1'), isNull);
      expect(manager.isAttached('p1'), isFalse);
    });

    test('remove forgets entry', () {
      manager.registerEntry('p1', WebViewEntry());

      manager.remove('p1');

      expect(manager.has('p1'), isFalse);
      expect(manager.controller('p1'), isNull);
      expect(manager.activePanelIds, isEmpty);
    });

    test('disposeAll clears all entries', () {
      manager.registerEntry('p1', WebViewEntry());
      manager.registerEntry('p2', WebViewEntry());

      manager.disposeAll();

      expect(manager.activePanelIds, isEmpty);
      expect(manager.has('p1'), isFalse);
      expect(manager.has('p2'), isFalse);
    });

    test('runJavaScript returns null for unknown panel', () async {
      expect(await manager.runJavaScript('missing', '1 + 1'), isNull);
      expect(
        await manager.runJavaScriptReturningResult('missing', '1 + 1'),
        isNull,
      );
      expect(await manager.currentUrl('missing'), isNull);
      expect(await manager.pageTitle('missing'), isNull);
    });

    test(
      'delegates JavaScript and metadata calls to registered entry',
      () async {
        final calls = <String>[];
        manager.registerEntry(
          'p1',
          WebViewEntry(
            runJavaScript: (js) async => calls.add('run:$js'),
            runJavaScriptReturningResult: (js) async {
              calls.add('result:$js');
              return 'ok';
            },
            currentUrl: () async => 'https://example.com',
            pageTitle: () async => 'Example',
          ),
        );

        expect(
          await manager.runJavaScript('p1', 'window.scrollTo(0, 100)'),
          isNull,
        );
        expect(
          await manager.runJavaScriptReturningResult('p1', 'document.title'),
          'ok',
        );
        expect(await manager.currentUrl('p1'), 'https://example.com');
        expect(await manager.pageTitle('p1'), 'Example');
        expect(calls, ['run:window.scrollTo(0, 100)', 'result:document.title']);
      },
    );

    group('YoloNewTab channel serialization', () {
      late _MockPlatformWebViewController platform;
      late List<String> events;
      late List<Completer<void>> addGates;

      setUp(() {
        platform = _MockPlatformWebViewController();
        when(
          () => platform.setPlatformNavigationDelegate(any()),
        ).thenAnswer((_) async {});
        events = <String>[];
        addGates = <Completer<void>>[];
        when(
          () => platform.removeJavaScriptChannel(any()),
        ).thenAnswer((_) async {
          events.add('remove');
        });
        when(() => platform.addJavaScriptChannel(any())).thenAnswer((_) {
          events.add('add');
          final gate = Completer<void>();
          addGates.add(gate);
          return gate.future;
        });
        manager.register('p1', WebViewController.fromPlatform(platform));
      });

      test('concurrent ensure calls never interleave add before remove', () async {
        final f1 = manager.ensureYoloNewTabChannel('p1', (_) {});
        final f2 = manager.ensureYoloNewTabChannel('p1', (_) {});

        // Let both queued ops run up to the blocked first add.
        await pumpEventQueue();
        // The second remove must wait until the first add completed —
        // otherwise WebKit raises the duplicate-handler NSException.
        expect(events, ['remove', 'add']);
        expect(addGates, hasLength(1));

        addGates.first.complete();
        await f1;
        await pumpEventQueue();
        expect(addGates, hasLength(2));
        addGates[1].complete();
        await f2;
        expect(events, ['remove', 'add', 'remove', 'add']);
      });

      test('remove is ordered after a pending ensure', () async {
        final ensure = manager.ensureYoloNewTabChannel('p1', (_) {});

        manager.remove('p1');
        await pumpEventQueue();
        expect(events, ['remove', 'add']);

        addGates.first.complete();
        await ensure;
        // Entry is already gone, but the serialized removal still ran.
        await pumpEventQueue();
        expect(events, ['remove', 'add', 'remove']);
      });

      test('detach is ordered after a pending ensure', () async {
        final ensure = manager.ensureYoloNewTabChannel('p1', (_) {});

        manager.detach('p1');
        await pumpEventQueue();

        addGates.first.complete();
        await ensure;
        await pumpEventQueue();
        expect(events, ['remove', 'add', 'remove']);
      });
    });

    group('detached retention TTL', () {
      var now = DateTime(2024, 1, 1, 12);
      late WebViewManager clocked;

      setUp(() {
        now = DateTime(2024, 1, 1, 12);
        clocked = WebViewManager.testInstance(clock: () => now);
      });

      tearDown(() {
        clocked.disposeAll();
        WebpagePluginBase.controllers.clear();
      });

      test('keeps detached controller until the retention TTL expires', () {
        final controller = _controller();
        WebpagePluginBase.controllers['p1'] = controller;
        clocked.register('p1', controller);

        clocked.detach('p1');
        expect(clocked.has('p1'), isTrue);
        expect(clocked.isAttached('p1'), isFalse);

        now = now.add(
          WebViewManager.kDetachedRetentionTTL - const Duration(seconds: 1),
        );
        clocked.evictExpiredDetachedNow();

        expect(clocked.has('p1'), isTrue);
        expect(clocked.controller('p1'), same(controller));
        expect(WebpagePluginBase.controllers['p1'], same(controller));
      });

      test('evicts and disposes controller after the retention TTL', () {
        final controller = _controller();
        WebpagePluginBase.controllers['p1'] = controller;
        clocked.register('p1', controller);

        clocked.detach('p1');
        now = now.add(
          WebViewManager.kDetachedRetentionTTL + const Duration(seconds: 1),
        );
        clocked.evictExpiredDetachedNow();

        expect(clocked.has('p1'), isFalse);
        expect(clocked.controller('p1'), isNull);
        expect(WebpagePluginBase.controllers, isNot(contains('p1')));
        expect(clocked.activePanelIds, isEmpty);
      });

      test('reattach within TTL clears eviction and keeps the controller', () {
        final controller = _controller();
        clocked.register('p1', controller);
        clocked.detach('p1');

        // Board switch back: the widget re-registers the same controller.
        clocked.register('p1', controller);

        now = now.add(const Duration(minutes: 30));
        clocked.evictExpiredDetachedNow();

        expect(clocked.has('p1'), isTrue);
        expect(clocked.isAttached('p1'), isTrue);
        expect(clocked.controller('p1'), same(controller));
      });

      test('remove (panel delete) disposes immediately, no grace period', () {
        final controller = _controller();
        WebpagePluginBase.controllers['p1'] = controller;
        clocked.register('p1', controller);
        clocked.detach('p1');

        clocked.remove('p1');

        expect(clocked.has('p1'), isFalse);
        expect(WebpagePluginBase.controllers, isNot(contains('p1')));

        // A later eviction pass must not resurrect or double-dispose it.
        now = now.add(const Duration(hours: 1));
        clocked.evictExpiredDetachedNow();
        expect(clocked.has('p1'), isFalse);
      });

      test('entry detached twice keeps the original detach time', () {
        final controller = _controller();
        WebpagePluginBase.controllers['p1'] = controller;
        clocked.register('p1', controller);

        clocked.detach('p1');
        now = now.add(const Duration(minutes: 3));
        clocked.detach('p1');
        now = now.add(const Duration(minutes: 2));
        // 5 min since the FIRST detach -> expired.
        clocked.evictExpiredDetachedNow();
        expect(clocked.has('p1'), isFalse);
      });
    });
  });
}

WebViewController _controller() {
  final platform = _MockPlatformWebViewController();
  when(
    () => platform.setPlatformNavigationDelegate(any()),
  ).thenAnswer((_) async {});
  return WebViewController.fromPlatform(platform);
}
