import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

abstract class ChatMicHandler {
  bool get isAvailable;

  Future<void> start(
    BuildContext context, {
    required ChatSessionConfig config,
    required void Function({required bool recording, required bool transcribing})
    updateState,
    required Future<void> Function(String title, String message) showError,
  });

  Future<void> stop({
    required ChatSessionConfig config,
    required void Function(String transcript) onTranscript,
    required VoidCallback onFinished,
  });

  Future<void> dispose();
}
