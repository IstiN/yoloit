import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

class MobileBoardApp extends StatelessWidget {
  const MobileBoardApp({
    super.key,
    this.initialRemoteUrl,
    this.initialRemoteToken,
    this.boardCubit,
  });

  final String? initialRemoteUrl;
  final String? initialRemoteToken;
  final BoardCubit? boardCubit;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'YoLoIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.instance.theme,
      home: Scaffold(
        body: SafeArea(
          child: _MobileRemoteBootstrap(
            initialRemoteUrl: initialRemoteUrl,
            initialRemoteToken: initialRemoteToken,
            child: const BoardView(),
          ),
        ),
      ),
    );
    final externalCubit = boardCubit;
    if (externalCubit != null) {
      return BlocProvider.value(value: externalCubit, child: app);
    }
    return BlocProvider(
      create:
          (_) => BoardCubit(
            historyStore: LocalBoardHistoryStore(),
            actorId: 'mobile',
          ),
      child: app,
    );
  }
}

class _MobileRemoteBootstrap extends StatefulWidget {
  const _MobileRemoteBootstrap({
    required this.child,
    this.initialRemoteUrl,
    this.initialRemoteToken,
  });

  final Widget child;
  final String? initialRemoteUrl;
  final String? initialRemoteToken;

  @override
  State<_MobileRemoteBootstrap> createState() => _MobileRemoteBootstrapState();
}

class _MobileRemoteBootstrapState extends State<_MobileRemoteBootstrap> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final remoteUrl = widget.initialRemoteUrl?.trim();
    if (remoteUrl == null || remoteUrl.isEmpty) return widget.child;
    return BlocListener<BoardCubit, BoardState>(
      listenWhen:
          (previous, current) =>
              !previous.isLoaded && current.isLoaded && !_started,
      listener: (context, state) {
        _started = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          unawaited(
            context
                .read<BoardCubit>()
                .connectRemoteBoards(
                  url: remoteUrl,
                  token: widget.initialRemoteToken,
                )
                .then(
                  (boards) => debugPrint(
                    '[MobileBoardApp] connected ${boards.length} remote board(s) from $remoteUrl',
                  ),
                )
                .catchError(
                  (Object error, StackTrace stackTrace) => debugPrint(
                    '[MobileBoardApp] failed to connect remote $remoteUrl: $error',
                  ),
                ),
          );
        });
      },
      child: widget.child,
    );
  }
}
