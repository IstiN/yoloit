import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_history_panel.dart';

void _paint(HistoryPanelPreviewPainter painter) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, const Size(48, 36));
  recorder.endRecording();
}

HistoryPanelPreviewPainter _painter({
  IconData? icon,
  String? shape,
  bool isSticky = false,
  bool deleted = false,
}) {
  return HistoryPanelPreviewPainter(
    icon: icon,
    color: Colors.amber,
    iconColor: Colors.blue,
    shape: shape,
    isSticky: isSticky,
    deleted: deleted,
  );
}

BoardHistoryEvent _event({
  required String type,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) {
  return BoardHistoryEvent(
    opId: 'op-1',
    boardId: 'board',
    type: type,
    entityType: 'panel',
    entityId: 'panel-1',
    actorId: 'tester',
    timestamp: DateTime.utc(2026, 5, 31, 12),
    revision: 1,
    before: before,
    after: after,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryPanelPreviewPainter.paint', () {
    test('paints the fallback icon and returns early', () {
      _paint(_painter(icon: Icons.add_box_outlined));
      _paint(_painter(icon: Icons.delete_outline_rounded, deleted: true));
    });

    test('paints a sticky note with and without the deleted strike', () {
      _paint(_painter(isSticky: true));
      _paint(_painter(isSticky: true, deleted: true));
    });

    test('paints all supported shape variants', () {
      _paint(_painter(shape: 'diamond'));
      _paint(_painter(shape: 'circle'));
      _paint(_painter(shape: 'triangle'));
      _paint(_painter(shape: 'diamond', deleted: true));
    });

    test('paints the default rounded rect for unknown shapes', () {
      _paint(_painter());
      _paint(_painter(shape: 'hexagon'));
      _paint(_painter(deleted: true));
    });
  });

  group('HistoryPanelPreviewPainter.shouldRepaint', () {
    test('repaints when any compared field changes', () {
      final base = _painter(shape: 'circle');
      expect(base.shouldRepaint(_painter(shape: 'circle')), isFalse);
      expect(base.shouldRepaint(_painter(shape: 'diamond')), isTrue);
      expect(base.shouldRepaint(_painter(icon: Icons.abc)), isTrue);
      expect(base.shouldRepaint(_painter(shape: 'circle', isSticky: true)),
          isTrue);
      expect(base.shouldRepaint(_painter(shape: 'circle', deleted: true)),
          isTrue);
      expect(
        base.shouldRepaint(
          const HistoryPanelPreviewPainter(
            color: Colors.red,
            iconColor: Colors.blue,
            shape: 'circle',
            isSticky: false,
            deleted: false,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const HistoryPanelPreviewPainter(
            color: Colors.amber,
            iconColor: Colors.green,
            shape: 'circle',
            isSticky: false,
            deleted: false,
          ),
        ),
        isTrue,
      );
    });
  });

  group('HistoryPanelPreview widget', () {
    Future<void> pumpPreview(
      WidgetTester tester, {
      required BoardHistoryEvent event,
      Map<String, dynamic>? snapshot,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: HistoryPanelPreview(
              event: event,
              snapshot: snapshot,
              fallbackIcon: Icons.history_rounded,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders the fallback icon when the snapshot is missing', (
      tester,
    ) async {
      await pumpPreview(tester, event: _event(type: 'update'));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders a panel snapshot with a shape', (tester) async {
      const panel = BoardPanelInstance(
        id: 'panel-1',
        type: 'board.shape',
        title: 'Shape',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
        state: {'shape': 'diamond'},
      );
      await pumpPreview(
        tester,
        event: _event(type: 'update', before: panel.toJson()),
        snapshot: panel.toJson(),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders a deleted sticky note snapshot', (tester) async {
      const panel = BoardPanelInstance(
        id: 'panel-1',
        type: 'board.sticky',
        title: 'Sticky',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
        state: {'text': 'hi'},
      );
      await pumpPreview(
        tester,
        event: _event(type: 'panel.deleted', before: panel.toJson()),
        snapshot: panel.toJson(),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('falls back to the icon for an unreadable snapshot', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        event: _event(type: 'update', before: const {'bogus': true}),
        snapshot: const {'bogus': true},
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
