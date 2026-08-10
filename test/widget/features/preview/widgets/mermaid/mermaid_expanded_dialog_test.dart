import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_expanded_dialog.dart';

// Minimal 1x1 red PNG (69 bytes), same fixture as the mermaid goldens.
final Uint8List _tinyPngRed = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0xC9, 0xFE, 0x92, 0xEF, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

// Minimal 1x1 blue PNG (69 bytes).
final Uint8List _tinyPngBlue = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0xF8, 0x0F,
  0x00, 0x01, 0x03, 0x01, 0x00, 0x08, 0x89, 0xC2, 0xEC, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 100 50"><rect width="100" height="50"/></svg>';

void main() {
  final colors = AppColorScheme.fromAccent(Colors.deepPurple);

  setUp(() {
    MermaidExpandedDialog.debugSvgToPngOverride = null;
  });

  tearDown(() {
    MermaidExpandedDialog.debugSvgToPngOverride = null;
  });

  Widget harness({String? svg, double targetWidth = 900}) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [colors]),
      home: MermaidExpandedDialog(
        initialPng: _tinyPngRed,
        svg: svg,
        targetWidth: targetWidth,
        aspectRatio: 2.0,
        colors: colors,
        backgroundColor: colors.background,
        backgroundColorHex: '#0D1117',
      ),
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    String? svg,
    double targetWidth = 900,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    await tester.pumpWidget(harness(svg: svg, targetWidth: targetWidth));
    await tester.pump();
  }

  testWidgets('does not refine when svg is null', (tester) async {
    var calls = 0;
    MermaidExpandedDialog.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async {
          calls++;
          return _tinyPngBlue;
        };

    await pumpDialog(tester, targetWidth: 2000);

    expect(find.text('Diagram preview'), findsOneWidget);
    expect(find.text('Refining...'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('does not refine when target width stays inline-sized', (
    tester,
  ) async {
    var calls = 0;
    MermaidExpandedDialog.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async {
          calls++;
          return _tinyPngBlue;
        };

    await pumpDialog(tester, svg: _svg, targetWidth: 900);

    expect(find.text('Refining...'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('refines at high resolution and swaps in the new png', (
    tester,
  ) async {
    String? seenSvg;
    double? seenWidth;
    String? seenBackground;
    MermaidExpandedDialog.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async {
          seenSvg = svg;
          seenWidth = width;
          seenBackground = backgroundColor;
          return _tinyPngBlue;
        };

    await tester.runAsync(() async {
      await pumpDialog(tester, svg: _svg, targetWidth: 2000);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find.text('Refining...').evaluate().isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for refinement to finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      await tester.pump();
    });

    expect(seenSvg, _svg);
    expect(seenWidth, 2000);
    expect(seenBackground, '#0D1117');
    expect(find.text('Refining...'), findsNothing);
    expect(
      find.textContaining('Failed to render higher resolution preview'),
      findsNothing,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows a non-fatal error banner when refinement fails', (
    tester,
  ) async {
    MermaidExpandedDialog.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async =>
            throw StateError('resvg exploded');

    await tester.runAsync(() async {
      await pumpDialog(tester, svg: _svg, targetWidth: 2000);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find
          .textContaining('Failed to render higher resolution preview')
          .evaluate()
          .isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for the refine error banner');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      await tester.pump();
    });

    expect(find.textContaining('resvg exploded'), findsOneWidget);
    expect(find.text('Refining...'), findsNothing);
    // The initial low-res image is still displayed.
    expect(find.byType(Image), findsOneWidget);
  });
}
