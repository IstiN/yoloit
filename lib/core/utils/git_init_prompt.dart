import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Checks whether [folderPath] contains a git repository.
/// If not, shows a dialog asking the user whether to run `git init`.
/// Always returns — the workspace is added regardless of the user's choice.
Future<void> maybePromptGitInit(BuildContext context, String folderPath) async {
  final gitDir = Directory('$folderPath/.git');
  if (gitDir.existsSync()) return; // already a git repo — nothing to do

  if (!context.mounted) return;

  final colors = context.appColors;
  final init = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border),
      ),
      title: Text(
        'No Git Repository',
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
      ),
      content: Text(
        'The folder "${_basename(folderPath)}" is not a git repository.\n'
        'Initialize one here?',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Skip', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Initialize Git',
            style: TextStyle(color: colors.primary),
          ),
        ),
      ],
    ),
  );

  if (init == true) {
    await Process.run('git', ['init', folderPath]);
  }
}

String _basename(String path) {
  final sep = path.contains('/') ? '/' : r'\';
  return path.split(sep).where((s) => s.isNotEmpty).last;
}
