import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/demo/web_demo_board.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

/// Minimal web app that hosts only the board.
///
/// Does not pull in terminal, workspace, file-editor, or collaboration cubits.
/// Desktop-only panels are rendered as placeholders by the capability-aware
/// plugin registry.
class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BoardCubit(historyStore: const AdapterBoardHistoryStore()),
      child: const _WebAppRoot(),
    );
  }
}

class _WebAppRoot extends StatefulWidget {
  const _WebAppRoot();

  @override
  State<_WebAppRoot> createState() => _WebAppRootState();
}

class _WebAppRootState extends State<_WebAppRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cubit = context.read<BoardCubit>();
        cubit.load().then((_) async {
          if (!mounted) return;
          final activeBoard = cubit.state.activeBoard;
          final boards = cubit.state.boards;
          // Seed a demo board only the very first time the web app launches.
          if (boards.isEmpty ||
              (activeBoard != null && activeBoard.panels.isEmpty)) {
            await WebDemoBoardBuilder.build(cubit);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MaterialApp(
      title: 'YoLoIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.instance.theme.copyWith(
        scaffoldBackgroundColor: colors.background,
      ),
      home: const Scaffold(
        body: BoardView(),
      ),
    );
  }
}
