import 'package:yoloit/features/board/model/board_models.dart';

/// Generates an SVG representation of a board layout.
///
/// This produces a structural SVG showing panel positions, sizes, titles,
/// and links between panels. Useful for LLM consumption and visual
/// documentation.
class BoardSvgExporter {
  const BoardSvgExporter._();

  /// Generate an SVG string for the given board.
  static String export(BoardDocument board) {
    if (board.panels.isEmpty) {
      return _wrap(800, 600, '');
    }

    // Calculate bounding box
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in board.panels) {
      if (p.hidden) continue;
      final b = p.bounds;
      if (b.x < minX) minX = b.x;
      if (b.y < minY) minY = b.y;
      if (b.x + b.width > maxX) maxX = b.x + b.width;
      if (b.y + b.height > maxY) maxY = b.y + b.height;
    }

    const padding = 40.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final width = maxX - minX;
    final height = maxY - minY;

    final buf = StringBuffer();

    // Styles
    buf.writeln('<defs>');
    buf.writeln('  <style>');
    buf.writeln('    .panel { fill: #1e1e2e; stroke: #45475a; stroke-width: 1.5; rx: 8; }');
    buf.writeln('    .panel-title-bg { fill: #313244; rx: 8; }');
    buf.writeln('    .panel-title { fill: #cdd6f4; font-family: sans-serif; font-size: 13px; font-weight: 600; }');
    buf.writeln('    .panel-type { fill: #6c7086; font-family: sans-serif; font-size: 10px; }');
    buf.writeln('    .panel-dim { fill: #585b70; font-family: monospace; font-size: 9px; }');
    buf.writeln('    .link { stroke: #89b4fa; stroke-width: 1.5; fill: none; stroke-dasharray: 4,3; }');
    buf.writeln('    .board-title { fill: #cdd6f4; font-family: sans-serif; font-size: 18px; font-weight: 700; }');
    buf.writeln('  </style>');
    buf.writeln('</defs>');

    // Board title
    buf.writeln('<text x="${padding}" y="${padding - 10}" class="board-title">'
        '${_esc(board.name)}</text>');

    // Links
    final panelMap = {for (final p in board.panels) p.id: p};
    for (final link in board.links) {
      final from = panelMap[link.fromPanelId];
      final to = panelMap[link.toPanelId];
      if (from == null || to == null) continue;
      final fx = from.bounds.x + from.bounds.width / 2 - minX;
      final fy = from.bounds.y + from.bounds.height / 2 - minY;
      final tx = to.bounds.x + to.bounds.width / 2 - minX;
      final ty = to.bounds.y + to.bounds.height / 2 - minY;
      buf.writeln('<line x1="$fx" y1="$fy" x2="$tx" y2="$ty" class="link"/>');
    }

    // Panels
    for (final p in board.panels) {
      if (p.hidden) continue;
      final x = p.bounds.x - minX;
      final y = p.bounds.y - minY;
      final w = p.bounds.width;
      final h = p.bounds.height;

      buf.writeln('<g>');
      // Panel body
      buf.writeln('  <rect x="$x" y="$y" width="$w" height="$h" class="panel"/>');
      // Title bar
      buf.writeln('  <rect x="$x" y="$y" width="$w" height="28" class="panel-title-bg"/>');
      // Title text
      buf.writeln('  <text x="${x + 10}" y="${y + 18}" class="panel-title">'
          '${_esc(p.title)}</text>');
      // Type label
      final shortType = p.type.replaceFirst('board.', '');
      buf.writeln('  <text x="${x + 10}" y="${y + 44}" class="panel-type">'
          '${_esc(shortType)}</text>');
      // Dimensions
      buf.writeln('  <text x="${x + w - 10}" y="${y + h - 6}" '
          'text-anchor="end" class="panel-dim">'
          '${w.toInt()}×${h.toInt()}</text>');
      buf.writeln('</g>');
    }

    return _wrap(width, height, buf.toString(), minX: minX, minY: minY);
  }

  static String _wrap(double width, double height, String body,
      {double minX = 0, double minY = 0}) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     width="${width.ceil()}" height="${height.ceil()}"
     viewBox="0 0 ${width.ceil()} ${height.ceil()}">
<rect width="100%" height="100%" fill="#11111b"/>
$body
</svg>''';
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
}
