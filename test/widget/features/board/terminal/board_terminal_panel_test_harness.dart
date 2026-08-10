import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_widget.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

BoardPanelInstance terminalPanel({
  String sessionId = '',
  String sessionName = '',
  String workingDir = '',
  List<String> envGroupIds = const [],
}) {
  return BoardPanelInstance(
    id: 'term-panel-1',
    type: kTerminalPluginTypeId,
    title: 'Terminal',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 520, height: 400),
    state: {
      'config': {
        'sessionId': sessionId,
        'sessionName': sessionName,
        'workingDir': workingDir,
        'envGroupIds': envGroupIds,
      },
    },
  );
}

AgentSession liveTerminalSession(
  String id, {
  String name = 'demo',
  String dir = '/tmp/demo',
}) {
  return AgentSession(
    id: id,
    type: AgentType.terminal,
    workspacePath: dir,
    status: AgentStatus.live,
    customName: name,
  );
}

/// Backend that never spawns a real process: sessions get an in-memory
/// output stream and an exit-code future that never completes.
class FakeTerminalBackend implements TerminalBackend {
  /// Closed via [closeIfLaunched] from the tests that install this backend.
  // ignore: close_sinks
  final output = StreamController<String>();

  /// When set, [launch] throws it instead of returning a process.
  Object? launchError;

  /// Number of processes successfully handed out by [launch].
  var launchCount = 0;

  /// Closes [output] only when a process was actually launched. Closing a
  /// controller whose stream never had a listener returns a future that
  /// never completes, which hangs test teardown.
  Future<void> closeIfLaunched() async {
    if (launchCount > 0) await output.close();
  }

  @override
  TerminalBackendMode get mode => TerminalBackendMode.local;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  }) async {
    final error = launchError;
    if (error != null) throw error;
    launchCount++;
    return TerminalProcess(
      output: output.stream,
      exitCode: Completer<int>().future,
    );
  }

  @override
  void write(String sessionId, String data) {}

  @override
  void resize(String sessionId, int columns, int rows) {}

  @override
  Future<void> kill(String sessionId) async {}
}

Widget buildTerminalPanelApp({
  required BoardPanelInstance panel,
  required BoardCubit cubit,
  ValueChanged<Map<String, dynamic>>? onUpdateState,
}) {
  // BoardCubit sits above the MaterialApp so dialogs pushed onto the root
  // navigator (e.g. the session history dialog) can also read it.
  return BlocProvider<BoardCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(
          width: 560,
          height: 480,
          child: BoardTerminalPanelWidget(
            panel: panel,
            onUpdateState: onUpdateState ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpTerminalPanel(
  WidgetTester tester, {
  required BoardPanelInstance panel,
  BoardCubit? cubit,
  ValueChanged<Map<String, dynamic>>? onUpdateState,
  bool withBoard = false,
}) async {
  final boardCubit = cubit ?? BoardCubit();
  if (withBoard) {
    boardCubit.emit(
      BoardState(
        boards: [BoardDocument(id: 'b1', name: 'Board 1', panels: [panel])],
        activeBoardId: 'b1',
        isLoaded: true,
      ),
    );
  }
  await tester.pumpWidget(
    buildTerminalPanelApp(
      panel: panel,
      cubit: boardCubit,
      onUpdateState: onUpdateState,
    ),
  );
  await tester.pump();
}
