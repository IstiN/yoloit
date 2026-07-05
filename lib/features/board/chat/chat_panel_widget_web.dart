import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Controller shared between the chat panel and its anchored assistant shell.
class ChatPanelController {
  Future<void> Function()? _startMic;
  VoidCallback? _focusInput;

  void _attach({
    required Future<void> Function() startMic,
    required VoidCallback focusInput,
  }) {
    _startMic = startMic;
    _focusInput = focusInput;
  }

  void _detach() {
    _startMic = null;
    _focusInput = null;
  }

  Future<void> startMic() => _startMic?.call() ?? Future<void>.value();

  void focusInput() => _focusInput?.call();
}

/// Web stub for [ChatPanelWidget].
///
/// The full chat panel depends on `record`, local CLI providers, settings UI
/// and other native-only code. On web it renders a placeholder and exposes
/// the static notifier surface used by board chrome.
class ChatPanelWidget extends StatefulWidget {
  const ChatPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
    this.onCreateLinkedPanel,
    this.remoteInfo,
    this.compact = false,
    this.controller,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final RemoteBoardInfo? remoteInfo;
  final bool compact;
  final ChatPanelController? controller;
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )?
  onCreateLinkedPanel;

  static final Map<String, ValueNotifier<bool>> processingNotifiers = {};
  static final ValueNotifier<int> processingChangeNotifier = ValueNotifier(0);

  @override
  State<ChatPanelWidget> createState() => _ChatPanelWidgetState();
}

class _ChatPanelWidgetState extends State<ChatPanelWidget> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'AI Chat is not available in the browser.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
