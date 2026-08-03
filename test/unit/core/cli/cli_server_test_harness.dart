import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Shared harness for CliServer integration-style unit tests: a real
/// [CliServer] bound to a real [BoardCubit] with an in-memory history store,
/// driven over raw HTTP on the loopback socket.
BoardPanelInstance stickyPanel(
  String id,
  String title, {
  double x = 0,
  double y = 0,
}) {
  return BoardPanelInstance(
    id: id,
    type: 'board.sticky',
    title: title,
    bounds: BoardPanelBounds(x: x, y: y, width: 300, height: 200),
  );
}

void registerEchoHandler(String typeId, List<String> actions) {
  CliServer.instance.registerPanelHandler(
    FakePanelHandler(
      typeId: typeId,
      supportedActions: actions,
      onAction: (action, args, panel) async =>
          CliActionResult(data: {'echoed': args['text']}),
    ),
  );
}

Future<BoardCubit> startServer({
  List<BoardPanelInstance> panels = const [],
  List<BoardPanelLink> links = const [],
}) async {
  final cubit = BoardCubit(
    historyStore: MemoryBoardHistoryStore(),
    actorId: 'cli-panels-test',
  );
  addTearDown(cubit.close);
  cubit.emit(
    BoardState(
      boards: [
        BoardDocument(id: 'board', name: 'Board', panels: panels, links: links),
      ],
      activeBoardId: 'board',
      isLoaded: true,
    ),
  );
  await CliServer.instance.start(cubit);
  return cubit;
}

Future<({int status, String body})> applyYaml(String yaml) {
  return httpRequest(
    'POST',
    '/api/boards/board/apply',
    body: yaml,
    contentType: 'text/yaml',
  );
}

Future<({int status, Map<String, dynamic> json})> applyYamlJson(
  String yaml,
) async {
  final res = await applyYaml(yaml);
  return (
    status: res.status,
    json: jsonDecode(res.body) as Map<String, dynamic>,
  );
}

Future<({int status, String body, Map<String, dynamic> json})> apiJson(
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  final res = await httpRequest(
    method,
    path,
    body: body == null ? null : jsonEncode(body),
  );
  return (
    status: res.status,
    body: res.body,
    json: jsonDecode(res.body) as Map<String, dynamic>,
  );
}

Future<({int status, String body})> httpRequest(
  String method,
  String path, {
  String? body,
  String contentType = 'application/json',
}) async {
  final port = CliServer.instance.port!;
  final socket = await Socket.connect('127.0.0.1', port);
  final encoded = body ?? '';
  socket.write(
    [
      '$method $path HTTP/1.1',
      'Host: 127.0.0.1:$port',
      'Content-Type: $contentType',
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
  await socket.close();
  final raw = utf8.decode(bytes);
  final split = raw.indexOf('\r\n\r\n');
  expect(split, greaterThanOrEqualTo(0));
  final head = raw.substring(0, split);
  final statusMatch = RegExp(r'^HTTP/\d\.\d\s+(\d+)').firstMatch(head);
  return (
    status: int.parse(statusMatch!.group(1)!),
    body: raw.substring(split + 4),
  );
}

class FakePanelHandler extends PanelCliHandler {
  FakePanelHandler({
    required this.typeId,
    required this.supportedActions,
    required this.onAction,
  });

  @override
  final String typeId;

  @override
  final List<String> supportedActions;

  final Future<CliActionResult> Function(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) onAction;

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) =>
      <String, dynamic>{'title': panel.title, 'state': panel.state};

  @override
  Map<String, CliActionHelp> get actionHelp => {
    for (final action in supportedActions)
      action: CliActionHelp(description: '$action description'),
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) => onAction(action, args, panel);
}
