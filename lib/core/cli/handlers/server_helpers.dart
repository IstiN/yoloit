import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardDocument? findBoard(BoardCubit cubit, String idOrName) {
  final boards = cubit.state.boards;
  final byId = boards.where((b) => b.id == idOrName).firstOrNull;
  if (byId != null) return byId;
  final byName =
      boards
          .where((b) => b.name.toLowerCase() == idOrName.toLowerCase())
          .firstOrNull;
  if (byName != null) return byName;
  return boards.where((b) => b.id.startsWith(idOrName)).firstOrNull;
}

BoardPanelInstance? findPanel(BoardDocument board, String idOrTitle) {
  final panels = board.panels;
  final byId = panels.where((p) => p.id == idOrTitle).firstOrNull;
  if (byId != null) return byId;
  final byTitle =
      panels
          .where((p) => p.title.toLowerCase() == idOrTitle.toLowerCase())
          .firstOrNull;
  if (byTitle != null) return byTitle;
  return panels.where((p) => p.id.startsWith(idOrTitle)).firstOrNull;
}

/// Parse a color string to a [Color].
/// - `null` → returns null (clear/no color)
/// - `#RRGGBB` / `#AARRGGBB` hex strings
/// - Named colors: red, green, blue, yellow, purple, pink, orange, teal, gray, white
/// - Falls back to [Colors.blue] for unrecognised values
Color? parseColor(String? s) {
  if (s == null || s == 'clear') return null;
  if (s.startsWith('#')) {
    final hex = s.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    if (value != null) {
      // If 6-digit hex, force full opacity
      return Color(hex.length == 6 ? (value | 0xFF000000) : value);
    }
  }
  const named = <String, int>{
    'red': 0xFFFF4444,
    'green': 0xFF44BB44,
    'blue': 0xFF4488FF,
    'yellow': 0xFFFFD644,
    'purple': 0xFFA855F7,
    'pink': 0xFFEC4899,
    'orange': 0xFFF97316,
    'teal': 0xFF14B8A6,
    'gray': 0xFF6B7280,
    'white': 0xFFF3F4F6,
  };
  final v = named[s.toLowerCase()];
  if (v != null) return Color(v);
  return Colors.blue;
}
