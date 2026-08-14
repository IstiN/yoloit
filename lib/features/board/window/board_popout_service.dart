import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Thin wrapper around `desktop_multi_window` for popping a board into a
/// separate native window. Uses raw MethodChannel so tests can compile
/// without importing the package's native code.
class BoardPopoutService {
  BoardPopoutService._();

  /// Test-only override: set to a custom implementation to avoid calling
  /// desktop_multi_window in tests.
  static Future<void> Function(BuildContext, BoardDocument)? debugOverride;

  static const _channel = MethodChannel('mixin.one/desktop_multi_window');

  static Future<void> popOut(
    BuildContext context,
    BoardDocument board,
  ) async {
    final override = debugOverride;
    if (override != null) {
      return override(context, board);
    }
    try {
      final windowId = await _channel.invokeMethod<String>(
        'createWindow',
        <String, Object?>{
          'arguments': board.id,
          'hiddenAtLaunch': false,
        },
      );
      if (windowId == null) throw StateError('createWindow returned null');
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
