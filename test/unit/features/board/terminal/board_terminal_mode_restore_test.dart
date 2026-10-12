// Regression test for "wheel scrolls the panel scrollback instead of the
// TUI after app restart".
//
// Root cause: board/runtime terminal sessions live in the yoloitd daemon,
// which survives an app crash/restart. On re-attach the Flutter client
// creates a FRESH xterm emulator and replays only the recent output ring.
// Mode-setting sequences the TUI emitted long ago (alternate buffer
// 1049/1047, mouse reporting 1000/1002/1003/1006) are gone from the ring,
// so the new emulator thinks the session is in the normal buffer with mouse
// reporting off — wheel gestures then scroll the local scrollback instead
// of being forwarded to the still-running TUI.
//
// Fix: the daemon tracks DEC private modes per session (session.go
// trackModes) and returns them from POST /sessions; the client re-applies
// them to the fresh emulator before subscribing to the output stream.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoxterm/core.dart' show MouseMode;
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

class _ModesBackend implements TerminalBackend {
  _ModesBackend({this.modes = const []});

  final List<int> modes;
  var launchCount = 0;

  @override
  TerminalBackendMode get mode => TerminalBackendMode.runtime;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  }) async {
    launchCount++;
    return TerminalProcess(
      output: const Stream<String>.empty(),
      exitCode: Completer<int>().future,
      attachedExisting: modes.isNotEmpty,
      attachedModes: modes,
    );
  }

  @override
  void write(String sessionId, String data) {}

  @override
  void resize(String sessionId, int columns, int rows) {}

  @override
  Future<void> kill(String sessionId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    TerminalBackendService.instance.debugBackendOverride = null;
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
  });

  test('buildTerminalModeRestoreSequence emits one CSI per mode', () {
    expect(buildTerminalModeRestoreSequence(const []), isEmpty);
    expect(
      buildTerminalModeRestoreSequence(const [1000, 1049]),
      '\x1b[?1000h\x1b[?1049h',
    );
  });

  test(
    're-attached session re-applies recorded modes to the fresh terminal',
    () async {
      final backend = _ModesBackend(modes: const [1049, 1000, 1006]);
      TerminalBackendService.instance.debugBackendOverride = backend;
      final manager = BoardTerminalSessionManager.instance;

      final session = await manager.ensureSession(
        const BoardTerminalConfig(
          sessionId: 'restore-modes',
          sessionName: 'tui',
          workingDir: '/tmp',
        ),
      );

      expect(backend.launchCount, 1);
      // Alt buffer restored → wheel gestures forward to the TUI instead of
      // scrolling the local scrollback.
      expect(session.terminal.isUsingAltBuffer, isTrue);
      expect(session.terminal.mouseMode, isNot(MouseMode.none));
    },
  );

  test('fresh session (no recorded modes) stays in the main buffer', () async {
    final backend = _ModesBackend();
    TerminalBackendService.instance.debugBackendOverride = backend;
    final manager = BoardTerminalSessionManager.instance;

    final session = await manager.ensureSession(
      const BoardTerminalConfig(
        sessionId: 'fresh-modes',
        sessionName: 'shell',
        workingDir: '/tmp',
      ),
    );

    expect(session.terminal.isUsingAltBuffer, isFalse);
  });
}
