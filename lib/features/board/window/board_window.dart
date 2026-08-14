import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Entry point for a popped-out board window.
///
/// This window runs a completely independent Flutter engine with its own
/// BoardCubit. The board is loaded from SharedPreferences by ID and saves
/// independently. No real-time sync with the main window — the popped-out
/// board lives exclusively in this window.
Future<void> boardWindowMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // desktop_multi_window passes ["multi_window", windowId, boardId].
  final boardId = args.length >= 3 ? args[2] : '';
  debugPrint('[BoardWindow] starting with boardId=$boardId args=$args');
  if (boardId.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('No board ID provided'))),
    ));
    return;
  }

  // Load all boards from shared storage and pick the one we need.
  final cubit = BoardCubit();
  await cubit.load();
  debugPrint('[BoardWindow] loaded ${cubit.state.boards.length} boards');
  final board = cubit.state.boards
      .where((b) => b.id == boardId)
      .firstOrNull;
  debugPrint('[BoardWindow] board found: ${board?.name}');

  if (board == null) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Board not found: $boardId')),
      ),
    ));
    return;
  }

  runApp(_BoardWindowApp(cubit: cubit, boardId: boardId));
}

class _BoardWindowApp extends StatelessWidget {
  const _BoardWindowApp({required this.cubit, required this.boardId});

  final BoardCubit cubit;
  final String boardId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.instance.theme,
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: Column(
            children: [
              _BoardWindowTitleBar(boardId: boardId),
              Expanded(child: const BoardView()),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardWindowTitleBar extends StatelessWidget {
  const _BoardWindowTitleBar({required this.boardId});
  final String boardId;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<BoardCubit>();
    final board = cubit.state.boards
        .where((b) => b.id == boardId)
        .firstOrNull;
    final name = board?.name ?? 'Board';

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close window',
            onPressed: () => exit(0),
          ),
        ],
      ),
    );
  }
}
