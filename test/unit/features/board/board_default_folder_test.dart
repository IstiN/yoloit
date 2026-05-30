import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('BoardDocument exposes default folder from metadata', () {
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      metadata: {'defaultFolder': '/repo'},
    );

    expect(board.defaultFolder, '/repo');
  });

  test('new chat and terminal panels inherit board default folder', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      metadata: {'defaultFolder': '/repo'},
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    await cubit.createChatPanel();
    await cubit.createTerminalPanel();

    final panels = cubit.state.activeBoard!.panels;
    final chat = panels.singleWhere((p) => p.type == ChatPanelPlugin.kTypeId);
    final terminal = panels.singleWhere(
      (p) => p.type == BoardTerminalPanelPlugin.kTypeId,
    );

    expect(chat.state['configured'], isTrue);
    expect((chat.state['config'] as Map)['workingDir'], '/repo');
    expect((terminal.state['config'] as Map)['workingDir'], '/repo');
  });

  test('explicit working dir overrides board default folder', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      metadata: {'defaultFolder': '/repo'},
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    await cubit.createChatPanel(workingDir: '/explicit');

    final chat = cubit.state.activeBoard!.panels.single;
    expect((chat.state['config'] as Map)['workingDir'], '/explicit');
  });

  test('file tree inherits board default folder', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      metadata: {'defaultFolder': '/repo'},
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    await cubit.createGenericPanel(FileTreePlugin.kTypeId);

    final fileTree = cubit.state.activeBoard!.panels.single;
    expect(fileTree.state['rootPath'], '/repo');
  });

  test('updateBoardDefaultFolder sets and clears metadata', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(id: 'board', name: 'Board');
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    await cubit.updateBoardDefaultFolder('board', '/repo');
    expect(cubit.state.activeBoard!.defaultFolder, '/repo');

    await cubit.updateBoardDefaultFolder('board', 'clear');
    expect(cubit.state.activeBoard!.defaultFolder, 'clear');

    await cubit.updateBoardDefaultFolder('board', '');
    expect(cubit.state.activeBoard!.defaultFolder, isEmpty);
  });
}
