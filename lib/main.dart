import 'dart:async' show unawaited, Completer;
import 'dart:io' show Platform, File, exit;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yoloit/app.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/real_llm_tool_test_runner.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

// CLI Handlers
import 'package:yoloit/core/cli/handlers/chat_handler.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/core/cli/handlers/files_handler.dart';
import 'package:yoloit/core/cli/handlers/filetree_handler.dart';
import 'package:yoloit/core/cli/handlers/kanban_handler.dart';
import 'package:yoloit/core/cli/handlers/note_handler.dart';
import 'package:yoloit/core/cli/handlers/playlist_handler.dart';
import 'package:yoloit/core/cli/handlers/run_configs_handler.dart';
import 'package:yoloit/core/cli/handlers/terminal_handler.dart';
import 'package:yoloit/core/cli/handlers/assistant_handler.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/core/cli/handlers/webpage_handler.dart';

// Managers and Cubits
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (RealLlmToolTestRunner.isRequested(args)) {
    exit(await RealLlmToolTestRunner.run(args));
  }

  // On macOS, media_kit's default `DynamicLibrary.open('Mpv.framework/Mpv')`
  // collides with media_kit_video's linked `@rpath/Mpv.framework/Versions/A/Mpv`
  // because dyld treats them as different lookup keys → loads Mpv twice →
  // duplicate ObjC class registration → SIGABRT in mpv core threads.
  //
  // Force absolute path matching the linker's resolved @rpath so dyld
  // deduplicates the dylib.
  String? libmpvPath;
  if (Platform.isMacOS) {
    final exe = Platform.resolvedExecutable;
    // .../YoLoIT.app/Contents/MacOS/YoLoIT  →  .../YoLoIT.app/Contents/Frameworks/Mpv.framework/Versions/A/Mpv
    final exeDir = File(exe).parent.path;
    final candidate = '$exeDir/../Frameworks/Mpv.framework/Versions/A/Mpv';
    if (File(candidate).existsSync()) {
      libmpvPath = candidate;
    }
  }
  MediaKit.ensureInitialized(libmpv: libmpvPath);

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
  unawaited(ProviderModelCatalogService.instance.load());

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(900, 600),
    center: true,
    title: 'YoLoIT',
    titleBarStyle: TitleBarStyle.hidden,
    // On macOS, window buttons (traffic lights) are shown natively in hidden mode.
    // On Windows/Linux, we render our own controls in _WindowControls widget.
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
