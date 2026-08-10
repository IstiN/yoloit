import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_base.dart';
import 'package:yoloit/features/board/ui/webview_overlays_vm.dart';

import '../../../unit/helpers/mock_board_cubit.dart';

// ── Fakes for the webview_flutter platform layer ─────────────────────────────

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController()
    : super.implementation(const PlatformWebViewControllerCreationParams());
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakePlatformWebViewController();

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakePlatformWebViewWidget(params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBoardCubit cubit;
  late TransformationController transformController;

  BoardPanelInstance webPanel(
    String id, {
    double x = 0,
    double y = 0,
    bool hidden = false,
  }) => BoardPanelInstance(
    id: id,
    type: WebpagePluginBase.kTypeId,
    title: 'Web $id',
    bounds: BoardPanelBounds(x: x, y: y, width: 400, height: 300),
    hidden: hidden,
    state: const {'url': 'https://example.com'},
  );

  void registerController(String id) {
    WebpagePluginBase.controllers[id] = WebViewController.fromPlatform(
      _FakePlatformWebViewController(),
    );
  }

  Future<void> pumpOverlays(
    WidgetTester tester,
    List<BoardPanelInstance> panels, {
    String? focusedPanelId,
    bool isInteracting = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: BlocProvider<BoardCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox.expand(
              child: WebViewOverlays(
                panels: panels,
                focusedPanelId: focusedPanelId,
                transformController: transformController,
                canvasOrigin: Offset.zero,
                isInteracting: isInteracting,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    WebViewPlatform.instance = _FakeWebViewPlatform();
    cubit = MockBoardCubit();
    when(
      () => cubit.stream,
    ).thenAnswer((_) => const Stream<BoardState>.empty());
    when(() => cubit.focusPanel(any())).thenAnswer((_) async {});
    transformController = TransformationController();
  });

  tearDown(() {
    transformController.dispose();
    WebpagePluginBase.controllers.clear();
    WebpagePluginBase.pendingCssZoom.clear();
  });

  testWidgets('renders an unfocused overlay per visible web panel', (
    tester,
  ) async {
    registerController('w1');
    registerController('w2');

    await pumpOverlays(tester, [webPanel('w1'), webPanel('w2', x: 420)]);

    expect(find.byKey(const ValueKey('wv-w1')), findsOneWidget);
    expect(find.byKey(const ValueKey('wv-w2')), findsOneWidget);
    // Default CSS zoom entries were queued for both panels.
    expect(WebpagePluginBase.pendingCssZoom['w1'], 1.0);
    expect(WebpagePluginBase.pendingCssZoom['w2'], 1.0);
  });

  testWidgets('skips hidden, controller-less and off-screen panels', (
    tester,
  ) async {
    registerController('visible');
    registerController('hidden');
    // 'no-controller' intentionally has no registered controller.
    registerController('offscreen');

    await pumpOverlays(tester, [
      webPanel('visible'),
      webPanel('hidden', hidden: true),
      webPanel('no-controller'),
      webPanel('offscreen', x: 5000),
    ]);

    expect(find.byKey(const ValueKey('wv-visible')), findsOneWidget);
    expect(find.byKey(const ValueKey('wv-hidden')), findsNothing);
    expect(find.byKey(const ValueKey('wv-no-controller')), findsNothing);
    expect(find.byKey(const ValueKey('wv-offscreen')), findsNothing);
  });

  testWidgets('tapping an unfocused overlay focuses its panel', (tester) async {
    registerController('w1');

    await pumpOverlays(tester, [webPanel('w1')]);

    await tester.tap(find.byKey(const ValueKey('wv-w1')));
    verify(() => cubit.focusPanel('w1')).called(1);
  });

  testWidgets('focused panel gets the top overlay instead of the unfocused one', (
    tester,
  ) async {
    registerController('w1');
    registerController('w2');

    await pumpOverlays(
      tester,
      [webPanel('w1'), webPanel('w2', x: 420)],
      focusedPanelId: 'w1',
    );

    expect(find.byKey(const ValueKey('wv-focused-w1')), findsOneWidget);
    expect(find.byKey(const ValueKey('wv-w1')), findsNothing);
    expect(find.byKey(const ValueKey('wv-w2')), findsOneWidget);
  });

  testWidgets('no focused overlay when the focused id is not a web panel', (
    tester,
  ) async {
    registerController('w1');

    await pumpOverlays(tester, [webPanel('w1')], focusedPanelId: 'other');

    expect(find.byKey(const ValueKey('wv-focused-other')), findsNothing);
    expect(find.byKey(const ValueKey('wv-w1')), findsOneWidget);
  });

  testWidgets('hides overlays while the board is being interacted with', (
    tester,
  ) async {
    registerController('w1');

    await pumpOverlays(tester, [webPanel('w1')], isInteracting: true);

    expect(find.byKey(const ValueKey('wv-w1')), findsNothing);
  });

  testWidgets('renders nothing when no web panels are present', (tester) async {
    await pumpOverlays(tester, const []);

    expect(find.byType(WebViewWidget), findsNothing);
  });
}
