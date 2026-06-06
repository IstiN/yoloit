import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardOverviewSection _section({
    required String label,
    List<BoardDocument> boards = const [],
    bool includesCreate = false,
  }) =>
      BoardOverviewSection(
        label: label,
        boards: boards,
        includesCreate: includesCreate,
      );

  group('BoardOverviewSectionedLayout.compute', () {
    test('returns valid layout for a single item', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: [1],
      );

      expect(layout.columns, 1);
      expect(layout.cardSize.width, greaterThan(0));
      expect(layout.cardSize.height, greaterThan(0));
      expect(layout.start.dx, greaterThanOrEqualTo(22));
      expect(layout.sectionTops.length, 1);
    });

    test('increases columns when more items fit', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(2000, 800),
        itemCounts: [10],
      );

      expect(layout.columns, greaterThan(1));
      expect(layout.cardSize.aspectRatio, closeTo(1.55, 0.01));
    });

    test('computes section tops for multiple sections', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1200, 1000),
        itemCounts: [2, 3],
      );

      expect(layout.sectionTops.length, 2);
      expect(layout.sectionTops[1], greaterThan(layout.sectionTops[0]));
    });

    test('handles empty sections gracefully', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1200, 1000),
        itemCounts: [0, 2, 0],
      );

      expect(layout.sectionTops.length, 3);
      expect(layout.itemCountForSection(0), 0);
      expect(layout.itemCountForSection(1), 2);
    });

    test('card size respects aspect ratio', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 1000),
        itemCounts: [4],
      );

      expect(
        layout.cardSize.width / layout.cardSize.height,
        closeTo(1.55, 0.01),
      );
    });
  });

  group('rectFor', () {
    test('returns correct rect for first item', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: [2],
      );
      final rect = layout.rectFor(0, 0);

      expect(rect.left, closeTo(layout.start.dx, 0.1));
      expect(rect.top, closeTo(layout.sectionTops[0], 0.1));
      expect(rect.width, closeTo(layout.cardSize.width, 0.1));
      expect(rect.height, closeTo(layout.cardSize.height, 0.1));
    });

    test('advances column for second item in same row', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(2000, 800),
        itemCounts: [4],
      );
      // Ensure we have at least 2 columns for this test to be meaningful.
      if (layout.columns >= 2) {
        final r0 = layout.rectFor(0, 0);
        final r1 = layout.rectFor(0, 1);
        expect(r1.left, closeTo(r0.left + layout.cardSize.width + layout.spacing, 0.1));
        expect(r1.top, closeTo(r0.top, 0.1));
      }
    });

    test('advances row when index exceeds column count', () {
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1200, 1000),
        itemCounts: [6],
      );
      final columns = layout.columns;
      final rFirstRow = layout.rectFor(0, 0);
      final rNextRow = layout.rectFor(0, columns);

      expect(
        rNextRow.top,
        closeTo(rFirstRow.top + layout.cardSize.height + layout.spacing, 0.1),
      );
    });
  });

  group('locationForBoard', () {
    test('finds board by id across sections', () {
      final board = BoardDocument(id: 'b1', name: 'Alpha');
      final sections = [
        _section(label: 'First', boards: [board]),
        _section(label: 'Second'),
      ];
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: sections.map((s) => s.boards.length).toList(),
      );

      final location = layout.locationForBoard(sections, 'b1');
      expect(location, isNotNull);
      expect(location!.sectionIndex, 0);
      expect(location.itemIndex, 0);
    });

    test('returns null when board is not found', () {
      final sections = [_section(label: 'First')];
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: [0],
      );

      expect(layout.locationForBoard(sections, 'missing'), isNull);
    });
  });

  group('createLocation', () {
    test('returns location in section marked with includesCreate', () {
      final sections = [
        _section(label: 'Recent'),
        _section(label: 'Create', includesCreate: true, boards: [
          BoardDocument(id: 'b1', name: 'One'),
        ]),
      ];
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: [0, 2],
      );

      final location = layout.createLocation(sections);
      expect(location, isNotNull);
      expect(location!.sectionIndex, 1);
      expect(location.itemIndex, 1);
    });

    test('returns null when no section includes create', () {
      final sections = [_section(label: 'Recent')];
      final layout = BoardOverviewSectionedLayout.compute(
        size: const Size(1000, 600),
        itemCounts: [0],
      );

      expect(layout.createLocation(sections), isNull);
    });
  });
}
