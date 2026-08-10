import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper_web.dart';

/// Signature for creating a board note panel from a sub-agent tool result.
typedef CreateAgentNotePanel =
    Future<void> Function({
      required BuildContext context,
      required String boardName,
      required String title,
      required String content,
      String? workingDir,
    });

/// Creates a board note panel from a sub-agent tool result.
///
/// A mutable top-level so tests can stub out the real `Process.run` call
/// (spawning processes inside the widget-test fake-async zone leaks timers).
CreateAgentNotePanel createAgentNotePanel = ChatSubagentNoteHelper.create;
