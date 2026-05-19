import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';

class _MockPlatformWebViewController extends Mock
    implements PlatformWebViewController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebViewManager', () {
    late WebViewManager manager;

    setUp(() {
      manager = WebViewManager.testInstance();
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
  });
}

WebViewController _controller() {
  final platform = _MockPlatformWebViewController();
  return WebViewController.fromPlatform(platform);
}
