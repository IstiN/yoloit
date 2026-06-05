import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardOverviewSection {
  const BoardOverviewSection({
    required this.label,
    required this.boards,
    this.subtitle,
    this.remoteUrl,
    this.includesCreate = false,
  });

  final String label;
  final String? subtitle;
  final String? remoteUrl;
  final List<BoardDocument> boards;
  final bool includesCreate;
}

class BoardOverviewItemLocation {
  const BoardOverviewItemLocation(this.sectionIndex, this.itemIndex);

  final int sectionIndex;
  final int itemIndex;
}

class BoardOverviewSectionedLayout {
  const BoardOverviewSectionedLayout({
    required this.columns,
    required this.cardSize,
    required this.start,
    required this.spacing,
    required this.sectionGap,
    required this.itemCounts,
    required this.sectionTops,
  });

  static const _aspectRatio = 1.55;
  static const _padding = 22.0;
  static const _spacing = 16.0;
  static const _sectionGap = 54.0;
  static const _firstSectionLabelClearance = 34.0;

  final int columns;
  final Size cardSize;
  final Offset start;
  final double spacing;
  final double sectionGap;
  final List<int> itemCounts;
  final List<double> sectionTops;

  int itemCountForSection(int sectionIndex) => itemCounts[sectionIndex];

  Rect rectFor(int sectionIndex, int index) {
    final col = index % columns;
    final row = index ~/ columns;
    return Rect.fromLTWH(
      start.dx + col * (cardSize.width + spacing),
      sectionTops[sectionIndex] + row * (cardSize.height + spacing),
      cardSize.width,
      cardSize.height,
    );
  }

  BoardOverviewItemLocation? locationForBoard(
    List<BoardOverviewSection> sections,
    String boardId,
  ) {
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final itemIndex = section.boards.indexWhere(
        (board) => board.id == boardId,
      );
      if (itemIndex >= 0) {
        return BoardOverviewItemLocation(sectionIndex, itemIndex);
      }
    }
    return null;
  }

  BoardOverviewItemLocation? createLocation(
    List<BoardOverviewSection> sections,
  ) {
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (section.includesCreate) {
        return BoardOverviewItemLocation(sectionIndex, section.boards.length);
      }
    }
    return null;
  }

  static BoardOverviewSectionedLayout compute({
    required Size size,
    required List<int> itemCounts,
  }) {
    final totalItemCount = itemCounts.fold<int>(0, (sum, count) => sum + count);
    final maxColumns = math.max(1, math.min(5, totalItemCount));
    final availableWidth = math.max(1.0, size.width - (_padding * 2));
    final availableHeight = math.max(
      1.0,
      size.height - (_padding * 2) - _firstSectionLabelClearance,
    );
    var bestColumns = 1;
    var bestSize = const Size(1, 1);
    var bestArea = 0.0;

    for (var columns = 1; columns <= maxColumns; columns++) {
      final sectionRows =
          itemCounts.map((count) => (count / columns).ceil()).toList();
      final totalRows = sectionRows.fold<int>(0, (sum, rows) => sum + rows);
      final activeSections = sectionRows.where((rows) => rows > 0).length;
      final gapHeight = math.max(0, activeSections - 1) * _sectionGap;
      final maxCardWidth =
          (availableWidth - ((columns - 1) * _spacing)) / columns;
      final maxCardHeight =
          (availableHeight -
              math.max(0, totalRows - activeSections) * _spacing -
              gapHeight) /
          math.max(1, totalRows);
      final cardWidth = math.max(
        1.0,
        math.min(maxCardWidth, maxCardHeight * _aspectRatio),
      );
      final cardHeight = cardWidth / _aspectRatio;
      final area = cardWidth * cardHeight;
      if (area > bestArea) {
        bestArea = area;
        bestColumns = columns;
        bestSize = Size(cardWidth, cardHeight);
      }
    }

    final sectionRows =
        itemCounts.map((count) => (count / bestColumns).ceil()).toList();
    final activeSections = sectionRows.where((rows) => rows > 0).length;
    final totalRows = sectionRows.fold<int>(0, (sum, rows) => sum + rows);
    final gridWidth =
        (bestColumns * bestSize.width) + ((bestColumns - 1) * _spacing);
    final gridHeight =
        (totalRows * bestSize.height) +
        (math.max(0, totalRows - activeSections) * _spacing) +
        (math.max(0, activeSections - 1) * _sectionGap);
    final start = Offset(
      math.max(_padding, (size.width - gridWidth) / 2),
      math.max(
        _padding + _firstSectionLabelClearance,
        (size.height - gridHeight) / 2 + (_firstSectionLabelClearance / 2),
      ),
    );
    final sectionTops = <double>[];
    var top = start.dy;
    for (final rows in sectionRows) {
      sectionTops.add(top);
      if (rows <= 0) continue;
      top +=
          (rows * bestSize.height) +
          (math.max(0, rows - 1) * _spacing) +
          _sectionGap;
    }
    return BoardOverviewSectionedLayout(
      columns: bestColumns,
      cardSize: bestSize,
      start: start,
      spacing: _spacing,
      sectionGap: _sectionGap,
      itemCounts: itemCounts,
      sectionTops: sectionTops,
    );
  }
}
