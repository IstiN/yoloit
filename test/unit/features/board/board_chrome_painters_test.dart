import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_grid_painter.dart';
import 'package:yoloit/features/board/ui/board_minimap.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';

void _paint(CustomPainter painter, [Size size = const Size(200, 120)]) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording();
}

const panelA = BoardPanelInstance(
  id: 'a',
  type: 'board.kanban',
  title: 'A',
  bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
);
const panelB = BoardPanelInstance(
  id: 'b',
  type: 'board.note.markdown',
  title: 'B',
  bounds: BoardPanelBounds(x: 300, y: 200, width: 120, height: 90),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardGridPainter', () {
    BoardGridPainter painter({
      TransformationController? transformCtrl,
      Offset origin = Offset.zero,
      double cellSize = 40,
      double spacing = 0,
      Color color = Colors.grey,
    }) {
      final ctrl = transformCtrl ?? TransformationController();
      if (transformCtrl == null) addTearDown(ctrl.dispose);
      return BoardGridPainter(
        transformCtrl: ctrl,
        origin: origin,
        cellSize: cellSize,
        spacing: spacing,
        color: color,
      );
    }

    test('shouldRepaint tracks every compared field', () {
      final shared = TransformationController();
      addTearDown(shared.dispose);
      final base = painter(transformCtrl: shared);

      expect(base.shouldRepaint(painter(transformCtrl: shared)), isFalse);
      expect(base.shouldRepaint(painter()), isTrue);
      expect(
        base.shouldRepaint(
          painter(transformCtrl: shared, origin: const Offset(8, 0)),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(transformCtrl: shared, cellSize: 42)),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(transformCtrl: shared, spacing: 4)),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(transformCtrl: shared, color: Colors.red)),
        isTrue,
      );
    });

    test('paint draws grid lines for identity and transformed matrices', () {
      _paint(painter());

      final transformed = TransformationController(
        Matrix4.identity()
          ..translate(17.0, -23.0)
          ..scale(1.5),
      );
      addTearDown(transformed.dispose);
      _paint(painter(transformCtrl: transformed, spacing: 8));
    });
  });

  group('BoardMiniMapPainter', () {
    final colors = AppColorScheme.fromAccent(Colors.indigo);
    const bounds = Rect.fromLTWH(-100, -100, 520, 420);
    const viewport = Rect.fromLTWH(0, 0, 200, 120);

    BoardMiniMapPainter painter({
      List<BoardPanelInstance>? panels,
      Set<String>? processingPanelIds,
      Rect boundsRect = bounds,
      Rect viewportRect = viewport,
      AppColorScheme? colorScheme,
    }) {
      return BoardMiniMapPainter(
        panels: panels ?? const [panelA, panelB],
        processingPanelIds: processingPanelIds ?? const {},
        bounds: boundsRect,
        viewportRect: viewportRect,
        colors: colorScheme ?? colors,
      );
    }

    test('shouldRepaint tracks every compared field', () {
      const panels = [panelA, panelB];
      const processing = {'a'};
      final base = BoardMiniMapPainter(
        panels: panels,
        processingPanelIds: processing,
        bounds: bounds,
        viewportRect: viewport,
        colors: colors,
      );

      expect(
        base.shouldRepaint(
          BoardMiniMapPainter(
            panels: panels,
            processingPanelIds: processing,
            bounds: bounds,
            viewportRect: viewport,
            colors: colors,
          ),
        ),
        isFalse,
      );
      expect(base.shouldRepaint(painter()), isTrue);
      expect(
        base.shouldRepaint(
          painter(panels: panels, processingPanelIds: processing),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          painter(
            panels: panels,
            processingPanelIds: processing,
            boundsRect: bounds.inflate(4),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          painter(
            panels: panels,
            processingPanelIds: processing,
            viewportRect: viewport.inflate(4),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          painter(
            panels: panels,
            processingPanelIds: processing,
            colorScheme: AppColorScheme.fromAccent(Colors.teal),
          ),
        ),
        isTrue,
      );
    });

    test('paint returns early for empty bounds', () {
      _paint(painter(boundsRect: Rect.zero));
    });

    test('paint draws panels, processing glow and the viewport', () {
      _paint(
        painter(
          panels: [panelA, panelB.copyWith(color: Colors.amber)],
          processingPanelIds: const {'a'},
        ),
      );
    });
  });

  group('BoardOverviewLinksPainter', () {
    const linkAB = BoardPanelLink(id: 'l1', fromPanelId: 'a', toPanelId: 'b');
    const bounds = Rect.fromLTWH(0, 0, 420, 290);

    BoardOverviewLinksPainter painter({
      List<BoardPanelLink> links = const [],
      List<BoardPanelInstance> panels = const [panelA, panelB],
      Rect boundsRect = bounds,
      double scale = 0.5,
      double dx = 10,
      double dy = 12,
      bool useViewport = false,
    }) {
      return BoardOverviewLinksPainter(
        links: links,
        panels: panels,
        bounds: boundsRect,
        scale: scale,
        dx: dx,
        dy: dy,
        useViewport: useViewport,
      );
    }

    test('shouldRepaint tracks every compared field', () {
      const links = [linkAB];
      const panels = [panelA, panelB];
      const base = BoardOverviewLinksPainter(
        links: links,
        panels: panels,
        bounds: bounds,
        scale: 0.5,
        dx: 10,
        dy: 12,
      );

      expect(
        base.shouldRepaint(
          const BoardOverviewLinksPainter(
            links: links,
            panels: panels,
            bounds: bounds,
            scale: 0.5,
            dx: 10,
            dy: 12,
          ),
        ),
        isFalse,
      );
      expect(base.shouldRepaint(painter()), isTrue);
      expect(
        base.shouldRepaint(painter(links: links, panels: panels)),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          painter(links: links, panels: panels, boundsRect: bounds.inflate(2)),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(links: links, panels: panels, scale: 0.6)),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(links: links, panels: panels, dx: 11)),
        isTrue,
      );
      expect(
        base.shouldRepaint(painter(links: links, panels: panels, dy: 13)),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          painter(links: links, panels: panels, useViewport: true),
        ),
        isTrue,
      );
    });

    test('paint skips dangling links and maps endpoints to the preview', () {
      _paint(
        painter(
          links: const [
            linkAB,
            BoardPanelLink(id: 'l2', fromPanelId: 'a', toPanelId: 'ghost'),
            BoardPanelLink(id: 'l3', fromPanelId: 'ghost', toPanelId: 'b'),
          ],
        ),
      );
    });

    test('paint draws raw board coordinates in viewport mode', () {
      _paint(painter(links: const [linkAB], useViewport: true));
    });
  });
}
