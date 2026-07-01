import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await CliServer.instance.stop();
  });

  test('POST /api/boards/:id/undo coalesces resize bursts', () async {
    final cubit = await _startServerWithResizedShape();

    final response = await _postJson(
      CliServer.instance.port!,
      '/api/boards/board/undo',
      const {},
    );

    expect(response['ok'], isTrue);
    expect(response['undone'], isTrue);
    expect(cubit.state.activeBoard!.panels.single.bounds.width, 120);
  });

  test('tools/yoloit board:undo calls running CLI server', () async {
    final cubit = await _startServerWithResizedShape();

    final result = await Process.run(
      'bash',
      ['tools/yoloit', 'board:undo', 'board'],
      environment: {'YOLOIT_CLI_PORT': '${CliServer.instance.port}'},
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final response =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(response['ok'], isTrue);
    expect(response['undone'], isTrue);
    expect(response['redoDepth'], 1);
    expect(cubit.state.activeBoard!.panels.single.bounds.width, 120);
  });

  test('POST /api/boards/:id/redo restores undone resize', () async {
    final cubit = await _startServerWithResizedShape();

    final undoResponse = await _postJson(
      CliServer.instance.port!,
      '/api/boards/board/undo',
      const {},
    );
    expect(undoResponse['ok'], isTrue);
    expect(cubit.state.activeBoard!.panels.single.bounds.width, 120);

    final redoResponse = await _postJson(
      CliServer.instance.port!,
      '/api/boards/board/redo',
      const {},
    );
    expect(redoResponse['ok'], isTrue);
    expect(redoResponse['redone'], isTrue);
    expect(redoResponse['redoDepth'], 0);
    expect(cubit.state.activeBoard!.panels.single.bounds.width, 260);
  });

  test('tools/yoloit board:redo calls running CLI server', () async {
    final cubit = await _startServerWithResizedShape();

    final undoResult = await Process.run(
      'bash',
      ['tools/yoloit', 'board:undo', 'board'],
      environment: {'YOLOIT_CLI_PORT': '${CliServer.instance.port}'},
    );
    expect(undoResult.exitCode, 0);

    final result = await Process.run(
      'bash',
      ['tools/yoloit', 'board:redo', 'board'],
      environment: {'YOLOIT_CLI_PORT': '${CliServer.instance.port}'},
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final response =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(response['ok'], isTrue);
    expect(response['redone'], isTrue);
    expect(cubit.state.activeBoard!.panels.single.bounds.width, 260);
  });
}

Future<BoardCubit> _startServerWithResizedShape() async {
  final historyStore = MemoryBoardHistoryStore();
  final cubit = BoardCubit(historyStore: historyStore, actorId: 'cli-test');
  addTearDown(cubit.close);
  cubit.emit(
    const BoardState(
      boards: [BoardDocument(id: 'board', name: 'Board')],
      activeBoardId: 'board',
      isLoaded: true,
    ),
  );
  const panel = BoardPanelInstance(
    id: 'shape-1',
    type: 'board.shape',
    title: 'Rhombus',
    bounds: BoardPanelBounds(x: 10, y: 20, width: 120, height: 120),
    state: {'shape': 'diamond'},
  );
  await cubit.addPanel(panel);
  await cubit.updatePanel(
    'shape-1',
    (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 180)),
  );
  await cubit.updatePanel(
    'shape-1',
    (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 260)),
  );

  await CliServer.instance.start(cubit);
  return cubit;
}

Future<Map<String, dynamic>> _postJson(
  int port,
  String path,
  Map<String, Object?> body,
) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final encoded = jsonEncode(body);
  socket.write(
    [
      'POST $path HTTP/1.1',
      'Host: 127.0.0.1:$port',
      'Content-Type: application/json',
      'Content-Length: ${utf8.encode(encoded).length}',
      'Connection: close',
      '',
      encoded,
    ].join('\r\n'),
  );
  await socket.flush();
  final bytes = await socket.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  final raw = utf8.decode(bytes);
  final split = raw.indexOf('\r\n\r\n');
  expect(split, greaterThanOrEqualTo(0));
  final head = raw.substring(0, split);
  final status = RegExp(r'^HTTP/\d\.\d\s+(\d+)').firstMatch(head);
  expect(status?.group(1), '200', reason: raw);
  return jsonDecode(raw.substring(split + 4)) as Map<String, dynamic>;
}
