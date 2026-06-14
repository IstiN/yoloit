import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart'
    show BoardLinkGeometry;

final _boardToolDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

// ─────────────────────────────────────────────────────────────────────────────
// Tool identifiers
// ─────────────────────────────────────────────────────────────────────────────

enum BoardToolId { select, multiSelect, draw, connect }

// ─────────────────────────────────────────────────────────────────────────────
// Abstract base
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract base for all board interaction tools.
///
/// Add a new tool by extending this class and registering an instance in
/// [kBoardTools].  The tool system is deliberately lightweight — tool-specific
/// ephemeral state (active stroke, pending connection, etc.) is managed by the
/// board view state, not here.
abstract class BoardTool {
  const BoardTool();

  BoardToolId get id;
  String get label;
  IconData get icon;

  /// Accent colour shown in the toolbar when the tool is active.
  Color get accentColor;

  /// Keyboard shortcut hint shown in the tooltip (optional).
  String? get shortcutHint => null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Concrete tools
// ─────────────────────────────────────────────────────────────────────────────

class SelectTool extends BoardTool {
  const SelectTool();

  @override
  BoardToolId get id => BoardToolId.select;

  @override
  String get label => 'Select';

  @override
  IconData get icon => Icons.touch_app_outlined;

  @override
  Color get accentColor => _boardToolDefaultColors.accentBlue;

  @override
  String? get shortcutHint => 'V';
}

class MultiSelectTool extends BoardTool {
  const MultiSelectTool();

  @override
  BoardToolId get id => BoardToolId.multiSelect;

  @override
  String get label => 'Select Many';

  @override
  IconData get icon => Icons.select_all;

  @override
  Color get accentColor => _boardToolDefaultColors.accentBlue;

  @override
  String? get shortcutHint => 'M';
}

class DrawTool extends BoardTool {
  const DrawTool();

  @override
  BoardToolId get id => BoardToolId.draw;

  @override
  String get label => 'Draw';

  @override
  IconData get icon => Icons.edit_outlined;

  @override
  Color get accentColor => _boardToolDefaultColors.primaryLight;

  @override
  String? get shortcutHint => 'D';
}

class ConnectTool extends BoardTool {
  const ConnectTool();

  @override
  BoardToolId get id => BoardToolId.connect;

  @override
  String get label => 'Connect';

  @override
  IconData get icon => Icons.account_tree_outlined;

  @override
  Color get accentColor => _boardToolDefaultColors.accentGreen;

  @override
  String? get shortcutHint => 'C';
}

/// The canonical ordered list of all available tools.
const List<BoardTool> kBoardTools = [
  SelectTool(),
  MultiSelectTool(),
  DrawTool(),
  ConnectTool(),
];

// ─────────────────────────────────────────────────────────────────────────────
// Draw tool settings (value object, immutable)
// ─────────────────────────────────────────────────────────────────────────────

class DrawSettings {
  const DrawSettings({
    this.strokeColor = Colors.deepPurpleAccent,
    this.strokeWidth = 3.0,
  });

  final Color strokeColor;
  final double strokeWidth;

  DrawSettings copyWith({Color? strokeColor, double? strokeWidth}) {
    return DrawSettings(
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect tool settings
// ─────────────────────────────────────────────────────────────────────────────

// BoardLinkGeometry is defined in board_models.dart and re-exported here
// via the import above.

class ConnectSettings {
  const ConnectSettings({
    this.geometry = BoardLinkGeometry.bezier,
    this.showArrow = true,
    this.color = Colors.lightBlueAccent,
  });

  final BoardLinkGeometry geometry;
  final bool showArrow;
  final Color color;

  ConnectSettings copyWith({
    BoardLinkGeometry? geometry,
    bool? showArrow,
    Color? color,
  }) {
    return ConnectSettings(
      geometry: geometry ?? this.geometry,
      showArrow: showArrow ?? this.showArrow,
      color: color ?? this.color,
    );
  }
}
