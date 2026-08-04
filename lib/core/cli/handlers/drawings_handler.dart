import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/board_svg_exporter.dart';
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Shared request context passed to every extracted drawings route handler.
class _DrawingsRequestContext {
  const _DrawingsRequestContext({
    required this.request,
    required this.cubit,
    required this.body,
    required this.json,
    required this.error,
    required this.scheduleRebuild,
    required this.parseColor,
  });

  final shelf.Request request;
  final BoardCubit cubit;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final shelf.Response Function(String) error;
  final void Function() scheduleRebuild;
  final Color? Function(String?) parseColor;
}

typedef _DrawingsRouteHandler =
    Future<shelf.Response> Function(_DrawingsRequestContext ctx, List<String> sub);

/// Handlers keyed by HTTP method. Keys are unique, so map lookup is
/// equivalent to the original if-chain.
const _drawingsRoutes = <String, _DrawingsRouteHandler>{
  'GET': _drawingsGet,
  'POST': _drawingsPost,
  'DELETE': _drawingsDelete,
};

Future<shelf.Response> handleDrawings(
  String method,
  List<String> sub,
  shelf.Request request,
  BoardCubit cubit, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  required void Function() scheduleRebuild,
  required Color? Function(String?) parseColor,
}) async {
  final handler = _drawingsRoutes[method];
  if (handler == null) return notFound('Unknown drawings route');
  final ctx = _DrawingsRequestContext(
    request: request,
    cubit: cubit,
    body: body,
    json: json,
    error: error,
    scheduleRebuild: scheduleRebuild,
    parseColor: parseColor,
  );
  return handler(ctx, sub);
}

Future<shelf.Response> _drawingsGet(
  _DrawingsRequestContext ctx,
  List<String> sub,
) async {
  // GET /api/drawings/svg?board=<id>  → SVG of drawings only
  final isSvgExport = sub.firstOrNull == 'svg';
  final boardId =
      ctx.request.url.queryParameters['board'] ??
      (isSvgExport ? sub.elementAtOrNull(1) : sub.firstOrNull);
  final board = (boardId != null && boardId.isNotEmpty)
      ? findBoard(ctx.cubit, boardId)
      : ctx.cubit.state.activeBoard;
  if (board == null) return ctx.error('Board not found');

  if (isSvgExport) {
    final svg = BoardSvgExporter.exportDrawings(board);
    return shelf.Response.ok(
      svg,
      headers: {'content-type': 'image/svg+xml; charset=utf-8'},
    );
  }
  return ctx.json({
    'ok': true,
    'boardId': board.id,
    'boardName': board.name,
    'count': board.drawings.length,
    'drawings': board.drawings.map(drawingToJson).toList(),
  });
}

Future<shelf.Response> _drawingsPost(
  _DrawingsRequestContext ctx,
  List<String> sub,
) async {
  try {
    return await handleDrawingsPost(
      ctx.request,
      ctx.cubit,
      sub,
      body: ctx.body,
      json: ctx.json,
      error: ctx.error,
      scheduleRebuild: ctx.scheduleRebuild,
      parseColor: ctx.parseColor,
    );
  } catch (e, st) {
    developer.log('[Drawings] POST error: $e\n$st');
    return ctx.json({'ok': false, 'error': e.toString()});
  }
}

Future<shelf.Response> _drawingsDelete(
  _DrawingsRequestContext ctx,
  List<String> sub,
) async {
  // DELETE /api/drawings/<board>/<id>  or  /api/drawings/<board>
  final boardId = sub.firstOrNull;
  if (boardId == null) return ctx.error('Missing board ID in path');
  final board = findBoard(ctx.cubit, boardId);
  if (board == null) return ctx.error('Board not found: $boardId');

  final drawingId = sub.length >= 2 ? sub[1] : null;
  if (drawingId != null) {
    await ctx.cubit.removeDrawing(drawingId, boardId: board.id);
    ctx.scheduleRebuild();
    return ctx.json({'ok': true, 'removed': drawingId});
  } else {
    // Clear all drawings
    for (final d in board.drawings) {
      await ctx.cubit.removeDrawing(d.id, boardId: board.id);
    }
    ctx.scheduleRebuild();
    return ctx.json({'ok': true, 'cleared': board.drawings.length});
  }
}

/// Outcome of a stroke builder in [handleDrawingsPost]: either an immediate
/// error response or the computed strokes + size.
class _StrokesBuild {
  const _StrokesBuild.error(this.errorResponse) : strokes = null, size = null;
  const _StrokesBuild.done(this.strokes, this.size) : errorResponse = null;

  final shelf.Response? errorResponse;
  final List<List<Offset>>? strokes;
  final Size? size;
}

/// Parsed inputs shared by the per-type stroke builders of
/// [handleDrawingsPost], so each builder takes a single parameter.
class _DrawingsPostContext {
  _DrawingsPostContext(this.requestBody, {required this.json})
    : type = (requestBody['type'] as String? ?? 'freehand').toLowerCase(),
      strokeWidth = (requestBody['width'] as num?)?.toDouble() ?? 3.0,
      posX = (requestBody['x'] as num?)?.toDouble() ?? 100.0,
      posY = (requestBody['y'] as num?)?.toDouble() ?? 100.0;

  final Map<String, dynamic> requestBody;
  final shelf.Response Function(Object) json;
  final String type;
  final double strokeWidth;
  final double posX;
  final double posY;

  ({double x1, double y1, double x2, double y2}) parseEndpoints() => (
    x1: (requestBody['x1'] as num?)?.toDouble() ?? posX,
    y1: (requestBody['y1'] as num?)?.toDouble() ?? posY,
    x2: (requestBody['x2'] as num?)?.toDouble() ?? posX + 200,
    y2: (requestBody['y2'] as num?)?.toDouble() ?? posY,
  );
}

typedef _StrokeBuilder =
    Future<_StrokesBuild> Function(_DrawingsPostContext ctx);

Future<_StrokesBuild> _buildLineStrokes(_DrawingsPostContext ctx) async {
  final ep = ctx.parseEndpoints();
  final result = lineToElement(ep.x1, ep.y1, ep.x2, ep.y2, ctx.strokeWidth);
  return _StrokesBuild.done(result.$1, result.$2);
}

Future<_StrokesBuild> _buildArrowStrokes(_DrawingsPostContext ctx) async {
  final ep = ctx.parseEndpoints();
  final result = arrowToElement(ep.x1, ep.y1, ep.x2, ep.y2, ctx.strokeWidth);
  return _StrokesBuild.done(result.$1, result.$2);
}

Future<_StrokesBuild> _buildCircleStrokes(_DrawingsPostContext ctx) async {
  final requestBody = ctx.requestBody;
  final cx = (requestBody['cx'] as num?)?.toDouble() ?? ctx.posX;
  final cy = (requestBody['cy'] as num?)?.toDouble() ?? ctx.posY;
  final r =
      (requestBody['r'] as num?)?.toDouble() ??
      (requestBody['radius'] as num?)?.toDouble() ??
      50.0;
  final result = circleToElement(cx, cy, r, ctx.strokeWidth);
  return _StrokesBuild.done(result.$1, result.$2);
}

Future<_StrokesBuild> _buildRectStrokes(_DrawingsPostContext ctx) async {
  final requestBody = ctx.requestBody;
  final rx = (requestBody['x'] as num?)?.toDouble() ?? ctx.posX;
  final ry = (requestBody['y'] as num?)?.toDouble() ?? ctx.posY;
  // Use 'rw' or 'rectWidth' for shape width; fall back to 'width' only if
  // no stroke-width was explicitly provided (to avoid conflict).
  final w =
      (requestBody['rw'] as num?)?.toDouble() ??
      (requestBody['rectWidth'] as num?)?.toDouble() ??
      (requestBody['w'] as num?)?.toDouble() ??
      200.0;
  final h = (requestBody['height'] as num?)?.toDouble() ?? 100.0;
  final result = rectToElement(rx, ry, w, h, ctx.strokeWidth);
  return _StrokesBuild.done(result.$1, result.$2);
}

Future<_StrokesBuild> _buildSvgStrokes(_DrawingsPostContext ctx) async {
  final requestBody = ctx.requestBody;
  final pathD =
      requestBody['d'] as String? ?? requestBody['path'] as String? ?? '';
  final svgStr = requestBody['svg'] as String?;
  final dStr = pathD.isNotEmpty
      ? pathD
      : (svgStr != null ? extractSvgPathD(svgStr) : '');
  if (dStr.isEmpty) {
    return _StrokesBuild.error(
      ctx.json({
        'ok': false,
        'error': 'Missing "d" (SVG path data) or "svg" field',
      }),
    );
  }
  final result = svgPathToElement(dStr, ctx.posX, ctx.posY, ctx.strokeWidth);
  if (result == null) {
    return _StrokesBuild.error(
      ctx.json({
        'ok': false,
        'error':
            'Failed to parse SVG path — check "d" syntax (M/L/C/Q/Z commands)',
      }),
    );
  }
  return _StrokesBuild.done(result.$1, result.$2);
}

Future<_StrokesBuild> _buildFileStrokes(_DrawingsPostContext ctx) async {
  final requestBody = ctx.requestBody;
  // Render all paths from an SVG file as a single drawing element
  final filePath =
      requestBody['file'] as String? ?? requestBody['path'] as String? ?? '';
  if (filePath.isEmpty) {
    return _StrokesBuild.error(
      ctx.json({
        'ok': false,
        'error': 'Missing "file" — provide path to SVG file',
      }),
    );
  }
  final svgFile = File(filePath);
  if (!svgFile.existsSync()) {
    return _StrokesBuild.error(
      ctx.json({'ok': false, 'error': 'SVG file not found: $filePath'}),
    );
  }
  final svgContent = await svgFile.readAsString();
  // Extract all d="" attributes and combine into one element per path
  final dMatches = RegExp(r'd="([^"]*)"').allMatches(svgContent);
  final allStrokes = <List<Offset>>[];
  var maxW = 0.0, maxH = 0.0;
  for (final m in dMatches) {
    final d = m.group(1) ?? '';
    if (d.isEmpty) continue;
    final r = svgPathToElement(d, 0, 0, ctx.strokeWidth);
    if (r != null) {
      allStrokes.addAll(r.$1);
      if (r.$2.width > maxW) maxW = r.$2.width;
      if (r.$2.height > maxH) maxH = r.$2.height;
    }
  }
  if (allStrokes.isEmpty) {
    return _StrokesBuild.error(
      ctx.json({'ok': false, 'error': 'No drawable paths found in SVG file'}),
    );
  }
  return _StrokesBuild.done(allStrokes, Size(maxW, maxH));
}

Future<_StrokesBuild> _buildFreehandStrokes(_DrawingsPostContext ctx) async {
  final rawPointsVal = ctx.requestBody['points'];
  final rawPoints = rawPointsVal is List
      ? rawPointsVal
      : rawPointsVal is String
      ? (jsonDecode(rawPointsVal) as List?)
      : null;
  if (rawPoints == null || rawPoints.isEmpty) {
    return _StrokesBuild.error(
      ctx.json({
        'ok': false,
        'error': 'Missing "points" for freehand — provide [[x,y],...]',
      }),
    );
  }
  final points = rawPoints.map((p) {
    final pt = p as List;
    return Offset(
      pt[0] is num ? (pt[0] as num).toDouble() : 0,
      pt[1] is num ? (pt[1] as num).toDouble() : 0,
    );
  }).toList();
  final result = freehandToElement(points, ctx.strokeWidth);
  return _StrokesBuild.done(result.$1, result.$2);
}

/// Stroke builders keyed by drawing `type`; any other type (including the
/// default `freehand`) falls back to [_buildFreehandStrokes].
final _strokeBuilders = <String, _StrokeBuilder>{
  'line': _buildLineStrokes,
  'arrow': _buildArrowStrokes,
  'circle': _buildCircleStrokes,
  'rect': _buildRectStrokes,
  'rectangle': _buildRectStrokes,
  'svg': _buildSvgStrokes,
  'file': _buildFileStrokes,
};

Offset _drawingAbsPos(_DrawingsPostContext ctx) {
  final requestBody = ctx.requestBody;
  final posX = ctx.posX;
  final posY = ctx.posY;
  final strokeWidth = ctx.strokeWidth;
  return switch (ctx.type) {
    'line' || 'arrow' => Offset(
      math.min(
            (requestBody['x1'] as num?)?.toDouble() ?? posX,
            (requestBody['x2'] as num?)?.toDouble() ?? posX + 200,
          ) -
          strokeWidth,
      math.min(
            (requestBody['y1'] as num?)?.toDouble() ?? posY,
            (requestBody['y2'] as num?)?.toDouble() ?? posY,
          ) -
          strokeWidth,
    ),
    'circle' => Offset(
      ((requestBody['cx'] as num?)?.toDouble() ?? posX) -
          ((requestBody['r'] as num?)?.toDouble() ?? 50.0) -
          strokeWidth,
      ((requestBody['cy'] as num?)?.toDouble() ?? posY) -
          ((requestBody['r'] as num?)?.toDouble() ?? 50.0) -
          strokeWidth,
    ),
    'rect' || 'rectangle' => Offset(
      (requestBody['x'] as num?)?.toDouble() ?? posX,
      (requestBody['y'] as num?)?.toDouble() ?? posY,
    ),
    _ => Offset(posX, posY),
  };
}

Future<shelf.Response> handleDrawingsPost(
  shelf.Request request,
  BoardCubit cubit,
  List<String> sub, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required void Function() scheduleRebuild,
  required Color? Function(String?) parseColor,
}) async {
  final requestBody = await body(request);
  final boardId =
      (requestBody['board'] as String?) ?? request.url.queryParameters['board'];
  final board = (boardId != null && boardId.isNotEmpty)
      ? findBoard(cubit, boardId)
      : cubit.state.activeBoard;
  if (board == null) return error('Board not found');

  final ctx = _DrawingsPostContext(requestBody, json: json);
  final colorStr = requestBody['color'] as String? ?? '#FFFFFF';
  final color = parseColor(colorStr) ?? const Color(0xFFFFFFFF);
  final strokeWidth = ctx.strokeWidth;

  final builder = _strokeBuilders[ctx.type] ?? _buildFreehandStrokes;
  final built = await builder(ctx);
  final errorResponse = built.errorResponse;
  if (errorResponse != null) return errorResponse;
  final strokes = built.strokes!;
  final size = built.size!;

  final absPos = _drawingAbsPos(ctx);

  final maxZ = board.drawings.fold<int>(
    0,
    (v, d) => d.zIndex > v ? d.zIndex : v,
  );
  final drawing = BoardDrawingElement(
    id: 'drawing-${DateTime.now().millisecondsSinceEpoch}',
    strokes: strokes,
    position: absPos,
    size: size,
    strokeColor: color,
    strokeWidth: strokeWidth,
    zIndex: maxZ + 1,
  );
  await cubit.addDrawing(drawing, boardId: board.id);
  scheduleRebuild();
  return json({
    'ok': true,
    'id': drawing.id,
    'boardId': board.id,
    'type': ctx.type,
    'strokeCount': strokes.length,
    'pointCount': strokes.fold<int>(0, (s, st) => s + st.length),
  });
}

Map<String, dynamic> drawingToJson(BoardDrawingElement d) => {
  'id': d.id,
  'position': [d.position.dx, d.position.dy],
  'size': [d.size.width, d.size.height],
  'strokeCount': d.strokes.length,
  'pointCount': d.strokes.fold<int>(0, (s, st) => s + st.length),
  'strokeColor':
      '#${d.strokeColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
  'strokeWidth': d.strokeWidth,
  'zIndex': d.zIndex,
  'hidden': d.hidden,
};

(List<List<Offset>>, Size) lineToElement(
  double x1,
  double y1,
  double x2,
  double y2,
  double sw,
) {
  final minX = math.min(x1, x2) - sw;
  final minY = math.min(y1, y2) - sw;
  final origin = Offset(minX, minY);
  final pts = [Offset(x1, y1) - origin, Offset(x2, y2) - origin];
  final size = Size((x2 - x1).abs() + sw * 2, (y2 - y1).abs() + sw * 2);
  return ([pts], size);
}

(List<List<Offset>>, Size) arrowToElement(
  double x1,
  double y1,
  double x2,
  double y2,
  double sw,
) {
  final angle = math.atan2(y2 - y1, x2 - x1);
  const headLen = 20.0;
  const headAngle = 0.4; // radians
  final hx1 = x2 - headLen * math.cos(angle - headAngle);
  final hy1 = y2 - headLen * math.sin(angle - headAngle);
  final hx2 = x2 - headLen * math.cos(angle + headAngle);
  final hy2 = y2 - headLen * math.sin(angle + headAngle);
  final minX = [x1, x2, hx1, hx2].reduce(math.min) - sw;
  final minY = [y1, y2, hy1, hy2].reduce(math.min) - sw;
  final maxX = [x1, x2, hx1, hx2].reduce(math.max) + sw;
  final maxY = [y1, y2, hy1, hy2].reduce(math.max) + sw;
  final origin = Offset(minX, minY);
  final shaft = [Offset(x1, y1) - origin, Offset(x2, y2) - origin];
  final head1 = [Offset(hx1, hy1) - origin, Offset(x2, y2) - origin];
  final head2 = [Offset(hx2, hy2) - origin, Offset(x2, y2) - origin];
  return ([shaft, head1, head2], Size(maxX - minX, maxY - minY));
}

(List<List<Offset>>, Size) circleToElement(
  double cx,
  double cy,
  double r,
  double sw,
) {
  const steps = 64;
  final minX = cx - r - sw;
  final minY = cy - r - sw;
  final origin = Offset(minX, minY);
  final pts = List.generate(steps + 1, (i) {
    final angle = 2 * math.pi * i / steps;
    return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)) - origin;
  });
  final size = Size((r + sw) * 2, (r + sw) * 2);
  return ([pts], size);
}

(List<List<Offset>>, Size) rectToElement(
  double rx,
  double ry,
  double w,
  double h,
  double sw,
) {
  final origin = Offset(rx - sw, ry - sw);
  final pts = [
    Offset(rx, ry) - origin,
    Offset(rx + w, ry) - origin,
    Offset(rx + w, ry + h) - origin,
    Offset(rx, ry + h) - origin,
    Offset(rx, ry) - origin,
  ];
  return ([pts], Size(w + sw * 2, h + sw * 2));
}

(Offset, Size) _computeBBox(List<Offset> points, double sw) {
  double minX = points.first.dx, minY = points.first.dy;
  double maxX = minX, maxY = minY;
  for (final p in points) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final origin = Offset(minX - sw, minY - sw);
  return (origin, Size(maxX - minX + sw * 2, maxY - minY + sw * 2));
}

(List<List<Offset>>, Size) freehandToElement(List<Offset> points, double sw) {
  if (points.isEmpty) return ([<Offset>[]], Size(sw * 2, sw * 2));
  final (origin, size) = _computeBBox(points, sw);
  final rel = points.map((p) => p - origin).toList();
  return ([rel], size);
}

/// Extract the `d` attribute from a simple SVG string.
String extractSvgPathD(String svg) {
  final match = RegExp(r'd="([^"]*)"').firstMatch(svg);
  return match?.group(1) ?? '';
}

/// Mutable state for [svgPathToElement]: the token stream cursor plus the
/// in-progress stroke geometry, so each path command is a tiny self-contained
/// method instead of one giant switch.
class _SvgPathParser {
  _SvgPathParser(this.tokens);

  final List<String> tokens;
  final strokes = <List<Offset>>[];
  List<Offset> current = [];
  double cx = 0, cy = 0;
  int i = 0;
  String cmd = 'M';

  static final _commandHandlers = <String, void Function(_SvgPathParser)>{
    'M': (p) => p._moveToAbs(),
    'm': (p) => p._moveToRel(),
    'L': (p) => p._lineToAbs(),
    'l': (p) => p._lineToRel(),
    'H': (p) => p._horizontalToAbs(),
    'h': (p) => p._horizontalToRel(),
    'V': (p) => p._verticalToAbs(),
    'v': (p) => p._verticalToRel(),
    'C': (p) => p._cubicTo(),
    'c': (p) => p._cubicTo(),
    'Q': (p) => p._quadTo(),
    'q': (p) => p._quadTo(),
  };

  void run() {
    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'[MLHVCSQTAZmlhvcsqtaz]').hasMatch(t)) {
        _handleCommandLetter(t);
        continue;
      }
      final handler = _commandHandlers[cmd];
      if (handler == null) {
        i++; // skip unknown
      } else {
        handler(this);
      }
    }
    if (current.isNotEmpty) strokes.add(current);
  }

  void _handleCommandLetter(String t) {
    i++;
    // Z/z need no arguments — handle immediately
    if (t == 'Z' || t == 'z') {
      if (current.length > 1) current.add(current.first);
      if (current.isNotEmpty) strokes.add(current);
      current = [];
    } else {
      cmd = t;
    }
  }

  double num() {
    final v = double.tryParse(tokens[i]) ?? 0;
    i++;
    return v;
  }

  void _moveToAbs() {
    if (current.isNotEmpty) strokes.add(current);
    cx = num();
    cy = num();
    current = [Offset(cx, cy)];
    cmd = 'L';
  }

  void _moveToRel() {
    if (current.isNotEmpty) strokes.add(current);
    cx += num();
    cy += num();
    current = [Offset(cx, cy)];
    cmd = 'l';
  }

  void _lineToAbs() {
    cx = num();
    cy = num();
    current.add(Offset(cx, cy));
  }

  void _lineToRel() {
    cx += num();
    cy += num();
    current.add(Offset(cx, cy));
  }

  void _horizontalToAbs() {
    cx = num();
    current.add(Offset(cx, cy));
  }

  void _horizontalToRel() {
    cx += num();
    current.add(Offset(cx, cy));
  }

  void _verticalToAbs() {
    cy = num();
    current.add(Offset(cx, cy));
  }

  void _verticalToRel() {
    cy += num();
    current.add(Offset(cx, cy));
  }

  // cubic bezier — approximate with 10 points
  void _cubicTo() {
    final rel = cmd == 'c';
    double coord(double c) => rel ? c + num() : num();
    final x1 = coord(cx), y1 = coord(cy);
    final x2 = coord(cx), y2 = coord(cy);
    final ex = coord(cx), ey = coord(cy);
    for (int s = 1; s <= 10; s++) {
      final tt = s / 10;
      current.add(
        Offset(
          cubicBezier(cx, x1, x2, ex, tt),
          cubicBezier(cy, y1, y2, ey, tt),
        ),
      );
    }
    cx = ex;
    cy = ey;
  }

  // quadratic bezier
  void _quadTo() {
    final rel = cmd == 'q';
    double coord(double c) => rel ? c + num() : num();
    final x1 = coord(cx), y1 = coord(cy);
    final ex = coord(cx), ey = coord(cy);
    for (int s = 1; s <= 10; s++) {
      final tt = s / 10;
      current.add(
        Offset(quadBezier(cx, x1, ex, tt), quadBezier(cy, y1, ey, tt)),
      );
    }
    cx = ex;
    cy = ey;
  }
}

/// Parse a subset of SVG path commands into strokes.
/// Supports: M, L, H, V, C (cubic bezier), Q (quadratic), Z, and lowercase variants.
(List<List<Offset>>, Size)? svgPathToElement(
  String d,
  double baseX,
  double baseY,
  double sw,
) {
  // Tokenize: split on command letters, keeping the letter
  final tokens = RegExp(
    r'[MLHVCSQTAZmlhvcsqtaz]|[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();

  final parser = _SvgPathParser(tokens)..run();
  final strokes = parser.strokes;
  if (strokes.isEmpty) return null;

  // Compute bounding box of all points
  final allPts = strokes.expand((s) => s).toList();
  final (origin, size) = _computeBBox(allPts, sw);
  final relStrokes = strokes
      .map((s) => s.map((p) => p - origin).toList())
      .toList();
  return (relStrokes, size);
}

double cubicBezier(double p0, double p1, double p2, double p3, double t) {
  final mt = 1 - t;
  return mt * mt * mt * p0 +
      3 * mt * mt * t * p1 +
      3 * mt * t * t * p2 +
      t * t * t * p3;
}

double quadBezier(double p0, double p1, double p2, double t) {
  final mt = 1 - t;
  return mt * mt * p0 + 2 * mt * t * p1 + t * t * p2;
}
