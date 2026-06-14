import 'dart:io' show Platform, File, exit;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yoloit/app.dart';
import 'package:yoloit/core/cli/real_llm_tool_test_runner.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/platform/macos_cli_setup_service.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/skills/yoloit_global_skills_service.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (RealLlmToolTestRunner.isRequested(args)) {
    exit(await RealLlmToolTestRunner.run(args));
  }

  // media_kit's default `DynamicLibrary.open('Mpv.framework/Mpv')` can fail
  // in Flutter debug launches because the relative framework path is not
  // always resolved from the app bundle. On macOS it can also collide with
  // media_kit_video's linked `@rpath/Mpv.framework/Versions/A/Mpv`
  // because dyld treats them as different lookup keys → loads Mpv twice →
  // duplicate ObjC class registration → SIGABRT in mpv core threads.
  //
  // Force an absolute app-bundle path when available.
  String? libmpvPath;
  if (Platform.isMacOS) {
    final exe = Platform.resolvedExecutable;
    // .../YoLoIT.app/Contents/MacOS/YoLoIT  →  .../YoLoIT.app/Contents/Frameworks/Mpv.framework/Versions/A/Mpv
    final exeDir = File(exe).parent.path;
    final candidate = '$exeDir/../Frameworks/Mpv.framework/Versions/A/Mpv';
    if (File(candidate).existsSync()) {
      libmpvPath = candidate;
    }
  } else if (Platform.isIOS) {
    final exe = Platform.resolvedExecutable;
    // .../Runner.app/Runner  →  .../Runner.app/Frameworks/Mpv.framework/Mpv
    final exeDir = File(exe).parent.path;
    final candidate = '$exeDir/Frameworks/Mpv.framework/Mpv';
    if (File(candidate).existsSync()) {
      libmpvPath = candidate;
    }
  }
  try {
    MediaKit.ensureInitialized(libmpv: libmpvPath);
  } catch (error, stackTrace) {
    debugPrint('MediaKit initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  // Init app-level file logger early (before FlutterError hook) so it can
  // capture errors that occur during startup.
  await AppLogger.instance.init();

  // Suppress Flutter keyboard state assertion errors that occur when the PTY
  // terminal emulator causes macOS to re-inject key events (duplicate KeyDown).
  // This is a known Flutter + terminal emulator issue and does not indicate a
  // real application bug.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('_pressedKeys.containsKey') ||
        msg.contains('physical key is already pressed') ||
        msg.contains('KeyDownEvent is dispatched')) {
      return; // suppress — terminal PTY duplicate key events
    }
    originalOnError?.call(details);
  };

  // Install logger hooks after FlutterError handler so AppLogger wraps it.
  AppLogger.instance.install();

  await ThemeManager.instance.load();
  await HotkeyRegistry.instance.load();
  await AppConfig.instance.load();
  // Ensure CLI symlinks and PATH entries are set up (macOS only, best-effort).
  unawaited(MacosCliSetupService.instance.ensureInstalled());
  // Auto-install the built-in YoLoIT skill into global agent harnesses.
  unawaited(
    YoloitGlobalSkillsService.instance.installOrUpdate().drain<void>(),
  );
  // Init TmuxService early so board terminal panels can reattach to existing
  // tmux sessions during the first frame — before TerminalCubit.initialize()
  // runs in its postFrameCallback.
  await TmuxService.instance.init();
  unawaited(ProviderModelCatalogService.instance.load());

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(900, 600),
    center: true,
    title: 'YoLoIT',
    // macOS titlebar styling is handled in MainFlutterWindow.swift.
    // Windows/Linux keep using the custom _WindowControls widget.
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (!args.contains('--headless')) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  ResourceMonitorService.instance.start();
  runApp(const App());
}
