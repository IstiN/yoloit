import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_web.dart';

Future<void> createAgentNotePanel({
  required BuildContext context,
  required String boardName,
  required String title,
  required String content,
  String? workingDir,
}) => ChatSubagentNoteHelper.create(
      context: context,
      boardName: boardName,
      title: title,
      content: content,
      workingDir: workingDir,
    );
