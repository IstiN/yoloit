import 'dart:io';

import 'package:flutter/material.dart';

abstract class ChatSubagentNoteHelper {
  static Future<void> create({
    required BuildContext context,
    required String boardName,
    required String title,
    required String content,
    String? workingDir,
  }) async {
    try {
      await Process.run(
        'yoloit',
        ['note:create', boardName, title, content],
        workingDirectory: workingDir,
        runInShell: true,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📋 Agent output → panel "$title"'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Silently ignore — panel creation is best-effort
    }
  }
}
