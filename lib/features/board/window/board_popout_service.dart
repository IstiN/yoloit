import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pop-out requires a desktop release build'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
