import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yoloit/app_mobile.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  PlatformDirs.setInstance(
    IosPlatformDirs(rootOverride: '${docs.path}/yoloit'),
  );
  await ThemeManager.instance.load();
  await AppConfig.instance.load();
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => WorkspaceCubit()),
        BlocProvider(create: (_) => TerminalCubit()..initialize()),
      ],
      child: const MobileBoardApp(),
    ),
  );
}
