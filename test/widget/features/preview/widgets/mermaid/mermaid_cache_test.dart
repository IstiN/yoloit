import 'dart:typed_data';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_cache.dart';

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

const _options = MermaidRenderOptions(backgroundColor: '#FFFFFF');

void main() {
  late _MockMermaidRenderer renderer;

  setUpAll(() {
    registerFallbackValue(const MermaidRenderOptions());
  });

  setUp(() {
    renderer = _MockMermaidRenderer();
    MermaidRasterizedDiagramCache.debugReset();
    MermaidRasterizedDiagramCache.debugSvgToPngOverride =
        (svg, {width, height, backgroundColor}) async => _tinyPng;
  });

  tearDown(() {
    MermaidRasterizedDiagramCache.debugReset();
    MermaidRasterizedDiagramCache.debugSvgToPngOverride = null;
  });

  void stubRender(String result) {
    when(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => result);
  }

  Future<MermaidRasterizedDiagram> load(
    String code, {
    double width = 900,
    String variant = '',
  }) {
    return MermaidRasterizedDiagramCache.load(
      renderer: renderer,
      code: code,
      width: width,
      options: _options,
      variant: variant,
    );
  }

  test('miss renders, stores, and resolves a diagram', () async {
    stubRender(_svg);

    final diagram = await load('flowchart TD; A --> B');

    expect(diagram.svg, _svg);
    expect(diagram.png, _tinyPng);
    // viewBox 100x50 -> aspect ratio 2.0.
    expect(diagram.aspectRatio, 2.0);
    expect(diagram.imageProvider, isA<MemoryImage>());

    final key = MermaidRasterizedDiagramCache.keyFor(
      'flowchart TD; A --> B',
      900,
    );
    expect(MermaidRasterizedDiagramCache.contains(key), isTrue);

    final peeked = MermaidRasterizedDiagramCache.peek(
      'flowchart TD; A --> B',
      900,
    );
    expect(identical(peeked, diagram), isTrue);
  });

  test('hit returns the cached future without re-rendering', () async {
    stubRender(_svg);

    final first = await load('flowchart TD; A --> B');
    final second = await load('flowchart TD; A --> B');

    expect(identical(first, second), isTrue);
    verify(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).called(1);
  });

  test('width and variant produce distinct cache entries', () async {
    stubRender(_svg);

    await load('graph LR; A --> B', width: 900);
    await load('graph LR; A --> B', width: 2200);
    await load('graph LR; A --> B', variant: 'dark');

    verify(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).called(3);
  });

  test('failed renders are dropped so a retry re-renders', () async {
    when(
      () => renderer.renderToSvg(any(), options: any(named: 'options')),
    ).thenThrow(StateError('boom'));

    await expectLater(load('bad diagram'), throwsStateError);

    // Let the unawaited drop-failed callback run.
    await pumpEventQueue();

    final key = MermaidRasterizedDiagramCache.keyFor('bad diagram', 900);
    expect(MermaidRasterizedDiagramCache.contains(key), isFalse);
    expect(MermaidRasterizedDiagramCache.peek('bad diagram', 900), isNull);

    // A retry after a failure goes through the full render path again.
    stubRender(_svg);
    final diagram = await load('bad diagram');
    expect(diagram.svg, _svg);
    expect(MermaidRasterizedDiagramCache.contains(key), isTrue);
  });

  test('evicts the eldest entries beyond the 24-entry limit', () async {
    stubRender(_svg);

    for (var i = 0; i < 25; i++) {
      await load('diagram $i');
    }

    expect(
      MermaidRasterizedDiagramCache.contains(
        MermaidRasterizedDiagramCache.keyFor('diagram 0', 900),
      ),
      isFalse,
    );
    expect(
      MermaidRasterizedDiagramCache.contains(
        MermaidRasterizedDiagramCache.keyFor('diagram 24', 900),
      ),
      isTrue,
    );
  });
}
