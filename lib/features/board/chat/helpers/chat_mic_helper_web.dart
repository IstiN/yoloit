import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/helpers/chat_mic_helper_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class ChatMicHandlerImpl implements ChatMicHandler {
  @override
  bool get isAvailable => false;

  @override
  Future<void> start(
    BuildContext context, {
    required ChatSessionConfig config,
    required void Function({required bool recording, required bool transcribing})
    updateState,
    required Future<void> Function(String title, String message) showError,
  }) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone is not available in the browser.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Future<void> stop({
    required ChatSessionConfig config,
    required void Function(String transcript) onTranscript,
    required VoidCallback onFinished,
  }) async {
    onFinished();
  }

  @override
  Future<void> dispose() async {
    // No-op on web.
  }
}
