import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yoloit/app_mobile.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  PlatformDirs.setInstance(
    IosPlatformDirs(rootOverride: '${docs.path}/yoloit'),
  );
  await ThemeManager.instance.load();
  await AppConfig.instance.load();
  const remoteUrl = String.fromEnvironment('YOLOIT_REMOTE_URL');
  const remoteToken = String.fromEnvironment('YOLOIT_REMOTE_TOKEN');
  runApp(
    const MobileBoardApp(
      initialRemoteUrl: remoteUrl,
      initialRemoteToken: remoteToken,
    ),
  );
}
