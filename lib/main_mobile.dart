import 'package:flutter/material.dart';
import 'package:yoloit/app_mobile.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
