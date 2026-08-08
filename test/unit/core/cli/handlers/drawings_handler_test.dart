import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/drawings_handler.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../helpers/mock_board_cubit.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(
      BoardDrawingElement(
        id: '',
        strokes: [],
        position: Offset.zero,
        size: Size.zero,
        strokeColor: Colors.black,
        strokeWidth: 1,
      ),
    );
  });

  group('drawingToJson', () {
    test('serializes a drawing element', () {
      final drawing = BoardDrawingElement(
        id: 'd1',
        strokes: [
          [const Offset(0, 0), const Offset(10, 10)],
        ],
        position: const Offset(5, 5),
        size: const Size(100, 50),
        strokeColor: const Color(0xFFFF0000),
        strokeWidth: 2.5,
        zIndex: 3,
      );
      final json = drawingToJson(drawing);
      expect(json['id'], 'd1');
      expect(json['position'], [5.0, 5.0]);
      expect(json['size'], [100.0, 50.0]);
      expect(json['strokeCount'], 1);
      expect(json['pointCount'], 2);
      expect(json['strokeColor'], '#ff0000');
      expect(json['strokeWidth'], 2.5);
      expect(json['zIndex'], 3);
      expect(json['hidden'], false);
    });
  });

  group('lineToElement', () {
    test('produces correct stroke and size', () {
      final (strokes, size) = lineToElement(10, 20, 110, 220, 3);
      expect(strokes.length, 1);
      expect(strokes.first.length, 2);
      expect(strokes.first.first, const Offset(3, 3));
      expect(size, const Size(106, 206));
    });
  });

  group('arrowToElement', () {
    test('produces shaft + 2 head strokes', () {
      final (strokes, size) = arrowToElement(0, 0, 100, 0, 2);
      expect(strokes.length, 3);
      expect(size.width, greaterThan(100));
    });
  });

  group('circleToElement', () {
    test('produces 65 points and correct size', () {
      final (strokes, size) = circleToElement(50, 50, 30, 2);
      expect(strokes.length, 1);
      expect(strokes.first.length, 65);
      expect(size, const Size(64, 64));
    });
  });

  group('rectToElement', () {
    test('produces closed rect stroke', () {
      final (strokes, size) = rectToElement(10, 20, 100, 50, 2);
      expect(strokes.length, 1);
      expect(strokes.first.length, 5);
      expect(size, const Size(104, 54));
    });
  });

  group('freehandToElement', () {
    test('computes bbox and returns relative points', () {
      final points = [
        const Offset(10, 10),
        const Offset(30, 5),
        const Offset(20, 40),
      ];
      final (strokes, size) = freehandToElement(points, 2);
      expect(strokes.first.first, const Offset(2, 7));
      expect(size.width, 24);
      expect(size.height, 39);
    });

    test('returns empty stroke for empty points', () {
      final (strokes, size) = freehandToElement([], 3);
      expect(strokes.first.isEmpty, true);
      expect(size, const Size(6, 6));
    });
  });

  group('extractSvgPathD', () {
    test('extracts d attribute', () {
      const svg = '<path d="M0 0 L10 10" />';
      expect(extractSvgPathD(svg), 'M0 0 L10 10');
    });

    test('returns empty string when missing', () {
      expect(extractSvgPathD('<path />'), '');
    });
  });

  group('svgPathToElement', () {
    test('parses simple line path', () {
      final result = svgPathToElement('M 10 10 L 100 100', 0, 0, 2);
      expect(result, isNotNull);
      final (strokes, size) = result!;
      expect(strokes.length, 1);
      expect(strokes.first.length, 2);
      expect(size.width, greaterThan(0));
    });

    test('parses cubic bezier', () {
      final result = svgPathToElement(
        'M0 0 C 10 10 20 20 30 30',
        0,
        0,
        1,
      );
      expect(result, isNotNull);
      expect(result!.$1.first.length, greaterThan(2));
    });

    test('parses quadratic bezier', () {
      final result = svgPathToElement('M0 0 Q 10 10 20 0', 0, 0, 1);
      expect(result, isNotNull);
      expect(result!.$1.first.length, greaterThan(2));
    });

    test('parses H and V commands', () {
      final result = svgPathToElement('M0 0 H 50 V 30', 0, 0, 1);
      expect(result, isNotNull);
      expect(result!.$1.first.length, 3);
    });

    test('handles relative commands', () {
      final result = svgPathToElement('m 10 10 l 20 0 h 10 v 10', 0, 0, 1);
      expect(result, isNotNull);
    });

    test('handles Z close path', () {
      final result = svgPathToElement('M0 0 L10 0 L10 10 Z', 0, 0, 1);
      expect(result, isNotNull);
    });

    test('returns null for empty path', () {
      expect(svgPathToElement('', 0, 0, 1), isNull);
    });

    test('handles mixed case with multiple strokes', () {
      final result = svgPathToElement(
        'M0 0 L10 10 M20 20 L30 30',
        0,
        0,
        1,
      );
      expect(result, isNotNull);
      expect(result!.$1.length, 2);
    });
  });

  group('cubicBezier', () {
    test('endpoints match control points at t=0 and t=1', () {
      expect(cubicBezier(0, 5, 10, 15, 0), 0);
      expect(cubicBezier(0, 5, 10, 15, 1), 15);
    });
  });

  group('quadBezier', () {
    test('endpoints match control points at t=0 and t=1', () {
      expect(quadBezier(0, 5, 10, 0), 0);
      expect(quadBezier(0, 5, 10, 1), 10);
    });
  });

  group('handleDrawings GET', () {
    late MockBoardCubit cubit;
    late BoardDocument board;

    setUp(() {
      cubit = MockBoardCubit();
      board = BoardDocument(
        id: 'board-1',
        name: 'Test Board',
        panels: [],
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [
              [const Offset(0, 0), const Offset(10, 10)],
            ],
            position: const Offset(0, 0),
            size: const Size(10, 10),
            strokeColor: Colors.black,
            strokeWidth: 1,
          ),
        ],
      );
      when(() => cubit.state).thenReturn(BoardState(boards: [board], activeBoardId: 'board-1'));
    });

    test('returns drawings list', () async {
      final request = shelf.Request('GET', Uri.parse('http://localhost/api/drawings?board=board-1'));
      final response = await handleDrawings(
        'GET',
        [],
        request,
        cubit,
        body: (_) async => {},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['count'], 1);
      expect((body['drawings'] as List).length, 1);
    });

    test('returns SVG export', () async {
      final request = shelf.Request('GET', Uri.parse('http://localhost/api/drawings/svg?board=board-1'));
      final response = await handleDrawings(
        'GET',
        ['svg'],
        request,
        cubit,
        body: (_) async => {},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 200);
      final svg = await response.readAsString();
      expect(svg.contains('<svg'), true);
    });

    test('returns error for missing board', () async {
      final request = shelf.Request('GET', Uri.parse('http://localhost/api/drawings?board=missing'));
      final response = await handleDrawings(
        'GET',
        [],
        request,
        cubit,
        body: (_) async => {},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 400);
    });
  });

  group('handleDrawings DELETE', () {
    late MockBoardCubit cubit;
    late BoardDocument board;

    setUp(() {
      cubit = MockBoardCubit();
      board = BoardDocument(
        id: 'board-1',
        name: 'Test Board',
        panels: [],
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [[const Offset(0, 0)]],
            position: const Offset(0, 0),
            size: const Size(10, 10),
            strokeColor: Colors.black,
            strokeWidth: 1,
          ),
        ],
      );
      when(() => cubit.state).thenReturn(BoardState(boards: [board], activeBoardId: 'board-1'));
      when(() => cubit.removeDrawing(any(), boardId: any(named: 'boardId')))
          .thenAnswer((_) async {});
    });

    test('removes a single drawing', () async {
      final request = shelf.Request('DELETE', Uri.parse('http://localhost/api/drawings/board-1/d1'));
      final response = await handleDrawings(
        'DELETE',
        ['board-1', 'd1'],
        request,
        cubit,
        body: (_) async => {},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 200);
      verify(() => cubit.removeDrawing('d1', boardId: 'board-1')).called(1);
    });

    test('clears all drawings', () async {
      final request = shelf.Request('DELETE', Uri.parse('http://localhost/api/drawings/board-1'));
      final response = await handleDrawings(
        'DELETE',
        ['board-1'],
        request,
        cubit,
        body: (_) async => {},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['cleared'], 1);
      verify(() => cubit.removeDrawing('d1', boardId: 'board-1')).called(1);
    });
  });

  group('handleDrawings POST freehand', () {
    late MockBoardCubit cubit;
    late BoardDocument board;

    setUp(() {
      cubit = MockBoardCubit();
      board = BoardDocument(
        id: 'board-1',
        name: 'Test Board',
        panels: [],
        drawings: [],
      );
      when(() => cubit.state).thenReturn(BoardState(boards: [board], activeBoardId: 'board-1'));
      when(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')))
          .thenAnswer((_) async {});
    });

    test('creates freehand drawing', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      final response = await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'freehand',
          'color': '#FF0000',
          'width': 2.0,
          'points': [[0, 0], [10, 10], [20, 5]],
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (s) => s == '#FF0000' ? const Color(0xFFFF0000) : null,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['type'], 'freehand');
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('returns error for missing points', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      final response = await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'freehand',
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => null,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });
  });

  group('handleDrawings POST shapes', () {
    late MockBoardCubit cubit;
    late BoardDocument board;

    setUp(() {
      cubit = MockBoardCubit();
      board = BoardDocument(
        id: 'board-1',
        name: 'Test Board',
        panels: [],
        drawings: [],
      );
      when(() => cubit.state).thenReturn(BoardState(boards: [board], activeBoardId: 'board-1'));
      when(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')))
          .thenAnswer((_) async {});
    });

    test('creates line', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'line',
          'x1': 0,
          'y1': 0,
          'x2': 100,
          'y2': 100,
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('creates arrow', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'arrow',
          'x1': 0,
          'y1': 0,
          'x2': 100,
          'y2': 0,
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('creates circle', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'circle',
          'cx': 50,
          'cy': 50,
          'r': 25,
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('creates rect', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'rect',
          'x': 10,
          'y': 20,
          'rw': 100,
          'height': 50,
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('creates rectangle (alias)', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'rectangle',
          'x': 0,
          'y': 0,
          'rw': 50,
          'height': 30,
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('creates SVG path', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'svg',
          'd': 'M0 0 L100 100',
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      verify(() => cubit.addDrawing(any(), boardId: 'board-1')).called(1);
    });

    test('returns error for invalid SVG path', () async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      final response = await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {
          'board': 'board-1',
          'type': 'svg',
          'd': '',
        },
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });

    test('returns error for missing board', () async {
      when(() => cubit.state).thenReturn(const BoardState());
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      final response = await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {'type': 'line'},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      expect(response.statusCode, 400);
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });
  });

  group('handleDrawings POST file', () {
    late MockBoardCubit cubit;
    late Directory tempDir;

    setUp(() {
      cubit = MockBoardCubit();
      final board = BoardDocument(
        id: 'board-1',
        name: 'Test Board',
        panels: [],
        drawings: [],
      );
      when(() => cubit.state).thenReturn(BoardState(boards: [board], activeBoardId: 'board-1'));
      when(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('drawings_file_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File writeSvg(String name, String contents) {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      file.writeAsStringSync(contents);
      return file;
    }

    Future<Map<String, dynamic>> postFile(Map<String, dynamic> requestBody) async {
      final request = shelf.Request('POST', Uri.parse('http://localhost/api/drawings'));
      final response = await handleDrawings(
        'POST',
        [],
        request,
        cubit,
        body: (_) async => {'board': 'board-1', 'type': 'file', ...requestBody},
        json: (o) => shelf.Response.ok(jsonEncode(o)),
        error: (s) => shelf.Response(400, body: s),
        notFound: (s) => shelf.Response(404, body: s),
        scheduleRebuild: () {},
        parseColor: (_) => Colors.black,
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    test('returns error when no file or path is provided', () async {
      final body = await postFile({});
      expect(body['ok'], false);
      expect(body['error'] as String, contains('Missing "file"'));
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });

    test('returns error when the SVG file does not exist', () async {
      final body = await postFile({'file': '${tempDir.path}/nope.svg'});
      expect(body['ok'], false);
      expect(body['error'] as String, contains('SVG file not found'));
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });

    test('renders every path of the SVG file as one drawing', () async {
      final svg = writeSvg(
        'two.svg',
        '<svg><path d="M0 0 L10 0"/><path d="M0 0 L100 0"/></svg>',
      );
      final body = await postFile({'file': svg.path, 'width': 2.0});
      expect(body['ok'], true);
      expect(body['type'], 'file');
      expect(body['strokeCount'], 2);

      final drawing =
          verify(() => cubit.addDrawing(captureAny(), boardId: 'board-1'))
              .captured
              .single as BoardDrawingElement;
      // Width tracks the widest path: 100 + 2 * strokeWidth.
      expect(drawing.size.width, 104);
      expect(drawing.strokes.length, 2);
    });

    test('accepts the "path" key as an alias for "file"', () async {
      final svg = writeSvg('alias.svg', '<svg><path d="M0 0 L5 5"/></svg>');
      final body = await postFile({'path': svg.path});
      expect(body['ok'], true);
      expect(body['strokeCount'], 1);
    });

    test('returns error when the SVG has no d attributes', () async {
      final svg = writeSvg('plain.svg', '<svg><rect x="0" y="0"/></svg>');
      final body = await postFile({'file': svg.path});
      expect(body['ok'], false);
      expect(body['error'] as String, contains('No drawable paths'));
      verifyNever(() => cubit.addDrawing(any(), boardId: any(named: 'boardId')));
    });

    test('skips empty and unparseable d attributes', () async {
      final svg = writeSvg(
        'bad.svg',
        '<svg><path d=""/><path d="garbage"/></svg>',
      );
      final body = await postFile({'file': svg.path});
      expect(body['ok'], false);
      expect(body['error'] as String, contains('No drawable paths'));
    });
  });
}
