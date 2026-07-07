import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

abstract class ChatSubagentNoteHelper {
  static Future<void> create({
    required BuildContext context,
    required String boardName,
    required String title,
    required String content,
    String? workingDir,
  }) async {
    try {
      await context.read<BoardCubit>().createMarkdownNote(
        title: title,
        markdown: content,
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
