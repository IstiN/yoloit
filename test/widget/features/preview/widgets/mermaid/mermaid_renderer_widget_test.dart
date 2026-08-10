import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_cache.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_expanded_dialog.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_renderer_widget.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_theme.dart';

class _MockMermaidRenderer extends Mock implements MermaidRenderer {}

// Minimal 1x1 red PNG (69 bytes), same fixture as the mermaid goldens.
final Uint8List _tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0xC9, 0xFE, 0x92, 0xEF, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 100 50"><rect width="100" height="50"/></svg>';

const _codeA = 'flowchart TD; A --> B';
const _codeB = 'sequenceDiagram; A->>B: hi';

MermaidThemeOptions _theme(String token) => MermaidThemeOptions(
  renderOptions: const MermaidRenderOptions(backgroundColor: '#FFFFFF'),
  cacheToken: token,
  canvasColor: Colors.white,
  scrimColor: Colors.black54,
);

void main() {
  final colors = AppColorScheme.fromAccent(Colors.deepPurple);

  late _MockMermaidRenderer renderer;

  setUpAll(() {
    registerFallbackValue(const MermaidRenderOptions());
  });

  setUp(() {
    renderer = _MockMermaidRenderer();
    MermaidRasterizedDiagramCache.debugReset();
    MermaidRasterizedDiagramCache.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async => _tinyPng;
    when(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _svg);
  });

  tearDown(() {
    MermaidRasterizedDiagramCache.debugReset();
    MermaidRasterizedDiagramCache.debugSvgToPngOverride = null;
  });

  Widget harness({String code = _codeA, String token = 'dark:test'}) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [colors]),
      home: Scaffold(
        body: Center(
          child: MermaidDiagram(
            code: code,
            renderer: renderer,
            colors: colors,
            mermaidTheme: _theme(token),
          ),
        ),
      ),
    );
  }

  /// Waits (on the real event loop) until [finder] matches or the 10 s
  /// budget expires. Rendering futures are real dart:io-free async work,
  /// but they do not complete inside the fake-async zone of testWidgets.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    String reason = '',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $reason');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    await tester.pump();
  }

  testWidgets('renders the diagram image after a successful render', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      expect(find.text('Rendering diagram…'), findsOneWidget);

      await pumpUntil(tester, find.byType(Image), reason: 'rendered image');

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Rendering diagram…'), findsNothing);
      verify(
        () => renderer.renderToSvg(_codeA, options: any(named: 'options')),
      ).called(1);
    });
  });

  testWidgets('shows the error frame when rendering fails', (tester) async {
    when(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).thenThrow(Exception('parse failure'));

    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(
        tester,
        find.textContaining('Mermaid error:'),
        reason: 'error frame',
      );

      expect(find.textContaining('parse failure'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  testWidgets('identical widget update does not re-render', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'rendered image');

      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      verify(
        () => renderer.renderToSvg(any(), options: any(named: 'options')),
      ).called(1);
    });
  });

  testWidgets('code change triggers a re-render', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'first render');

      await tester.pumpWidget(harness(code: _codeB));
      await pumpUntil(tester, find.byType(Image), reason: 'second render');

      verify(
        () => renderer.renderToSvg(_codeA, options: any(named: 'options')),
      ).called(1);
      verify(
        () => renderer.renderToSvg(_codeB, options: any(named: 'options')),
      ).called(1);
    });
  });

  testWidgets('theme token change re-renders with the new variant', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'first render');

      await tester.pumpWidget(harness(token: 'light:test'));
      await pumpUntil(tester, find.byType(Image), reason: 're-themed render');

      verify(
        () => renderer.renderToSvg(_codeA, options: any(named: 'options')),
      ).called(2);
    });
  });

  testWidgets('code change hydrates synchronously from a warm cache', (
    tester,
  ) async {
    // Pre-warm the cache for _codeB with the same variant.
    await MermaidRasterizedDiagramCache.load(
      renderer: renderer,
      code: _codeB,
      width: 900,
      options: _theme('dark:test').renderOptions,
      variant: 'dark:test',
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'first render');

      await tester.pumpWidget(harness(code: _codeB));
      // Hydration happens synchronously inside didUpdateWidget — the image
      // is already there after a single pump, with no extra render call.
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      verify(
        () => renderer.renderToSvg(_codeB, options: any(named: 'options')),
      ).called(1);
    });
  });

  testWidgets('copy action copies the source and shows a snackbar', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<String, dynamic>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'rendered image');
    });

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.text('Mermaid source copied'), findsOneWidget);
    expect(clipboardText, _codeA);
    // Drain the snackbar timer.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('open action shows the expanded preview dialog', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byType(Image), reason: 'rendered image');
    });

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(MermaidExpandedDialog), findsOneWidget);
    expect(find.text('Diagram preview'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(MermaidExpandedDialog), findsNothing);
  });
}
