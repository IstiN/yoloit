import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

// Conditional import: real desktop_multi_window only on native, stub in tests.
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.ui) 'package:yoloit/features/board/window/multi_window_stub.dart';

/// Thin wrapper around `desktop_multi_window` for popping a board into a
/// separate native window. Kept as a separate class so tests can override
/// the behavior without importing the package (which fails in test envs).
class BoardPopoutService {
  BoardPopoutService._();

  /// Test-only override: set to a custom implementation to avoid calling
  /// desktop_multi_window in tests.
  static Future<void> Function(BuildContext, BoardDocument)? debugOverride;

  static Future<void> popOut(
    BuildContext context,
    BoardDocument board,
  ) async {
    final override = debugOverride;
    if (override != null) {
      return override(context, board);
    }
    try {
      final window = await DesktopMultiWindow.createWindow(
        ['--board-window', board.id],
      );
      await window.setFrame(
        const Offset(100, 100) & const Size(1200, 800),
      );
      await window.setTitle(board.name);
      await window.show();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Board "${board.name}" opened in new window'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pop-out failed: $e')),
      );
    }
  }
}
