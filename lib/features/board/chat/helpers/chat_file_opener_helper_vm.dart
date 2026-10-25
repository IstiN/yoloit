import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper.dart';

abstract class ChatFileOpener {
  /// Test seam: overrides the OS-level "open file" command so unit tests
  /// can intercept it without spawning real processes.
  @visibleForTesting
  static Future<void> Function(String path)? debugFileOpener;

  static Future<void> open(
    String path, {
    CreatePreviewPanel? createPreviewPanel,
  }) async {
    if (path.isEmpty) return;
    final ext = path.split('.').last.toLowerCase();
    const boardPreviewable = {
      // images
      'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg',
      // video
      'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv',
      // audio
      'mp3', 'aac', 'wav', 'ogg', 'flac', 'm4a', 'opus', 'wma',
    };
    if (createPreviewPanel != null && boardPreviewable.contains(ext)) {
      final title = path.split('/').last;
      await createPreviewPanel(
        'board.file.preview',
        {'path': path, 'title': title},
        title,
      );
    } else {
      try {
        await (debugFileOpener ?? _openWithSystemHandler)(path);
      } catch (_) {
        // ignore open failures
      }
    }
  }

  static Future<void> _openWithSystemHandler(String path) async {
    await Process.run('open', [path]);
  }
}
