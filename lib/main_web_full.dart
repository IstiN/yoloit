import 'package:flutter/material.dart';
import 'package:yoloit/app_web.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

/// Full web entry point for the YoLoIT GitHub Pages demo.
///
/// Build with:
///   flutter build web --release --target lib/main_web_full.dart \
///     --base-href /yoloit/app/ --pwa-strategy none
///
/// This intentionally does NOT initialize desktop-only services:
/// window_manager, media_kit, TmuxService, ResourceMonitorService, CliServer.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort logging; file-backed logs are no-ops on web.
  await AppLogger.instance.init();
  AppLogger.instance.install();

  await ThemeManager.instance.load();
  await AgentConfigService.instance.load();

  runApp(const WebApp());
}
