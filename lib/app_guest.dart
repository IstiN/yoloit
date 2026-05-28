import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

import 'package:yoloit/features/collaboration/bloc/collaboration_cubit.dart';
import 'package:yoloit/features/collaboration/ui/guest_shell.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';

/// Minimal app for web / non-desktop platforms.
/// Only MindMapCubit + CollaborationCubit — no native platform code.
class GuestApp extends StatelessWidget {
  const GuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => MindMapCubit()),
        BlocProvider(
          create: (ctx) => CollaborationCubit(
            mindMapCubit: ctx.read<MindMapCubit>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'YoLoIT Space',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: colors.background,
          colorScheme: ColorScheme.dark(
            primary: colors.primary,
            secondary: colors.accentGreen,
            surface: colors.surface,
          ),
          extensions: <ThemeExtension<dynamic>>[colors],
          fontFamily: 'monospace',
        ),
        home: const GuestShell(),
      ),
    );
  }
}
