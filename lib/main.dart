import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yoloit/app.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
    await windowManager.show();
    await windowManager.focus();
  });

  ResourceMonitorService.instance.start();
  runApp(const App());
}
