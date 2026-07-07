import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/platform/url_opener.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/demo/web_demo_board.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/ui/shell/board_title_bar.dart';

/// Minimal web app that hosts only the board.
///
/// Does not pull in terminal, workspace, file-editor, or collaboration cubits.
/// Desktop-only panels are rendered as placeholders by the capability-aware
/// plugin registry.
class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => BoardCubit(historyStore: const AdapterBoardHistoryStore()),
        ),
        BlocProvider(create: (_) => WorkspaceCubit()),
      ],
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
  var _seeded = false;

  Future<void> _maybeSeedDemoBoard(BoardCubit cubit) async {
    if (_seeded) return;
    final state = cubit.state;
    if (!state.isLoaded) return;
    final activeBoard = state.activeBoard;
    final boards = state.boards;
    if (boards.isNotEmpty && activeBoard != null && activeBoard.panels.isNotEmpty) {
      _seeded = true;
      return;
    }
    _seeded = true;
    try {
      await WebDemoBoardBuilder.build(cubit);
    } catch (e, st) {
      debugPrint('[WebApp] failed to seed demo board: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _showSettings(BuildContext context) async {
    await SettingsPage.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'YoLoIT',
          debugShowCheckedModeBanner: false,
          theme: ThemeManager.instance.theme,
          localizationsDelegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(
            body: BlocListener<BoardCubit, BoardState>(
              listener: (context, state) {
                _maybeSeedDemoBoard(context.read<BoardCubit>());
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(
                    builder: (barContext) => BoardTitleBar(
                      onSettings: () => _showSettings(barContext),
                      trailing: const _DownloadReleasesButton(),
                    ),
                  ),
                  const Expanded(child: BoardView()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const String _downloadReleasesUrl =
    'https://github.com/IstiN/yoloit/releases/latest';

class _DownloadReleasesButton extends StatelessWidget {
  const _DownloadReleasesButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: 'Download YoLoIT for desktop',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(launchExternalUrl(_downloadReleasesUrl)),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surfaceHighlight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_outlined, size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Install',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
