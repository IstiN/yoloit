import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget_vm.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/widgets/yolo_badge_chat_shell.dart';

/// Web implementation of the floating YoLo assistant badge.
///
/// The desktop badge embeds the full [YoloAssistantWidget] which depends on
/// native speech recognition and local model runtimes. On the web we reuse the
/// same cloud-only [ChatPanelWidget] that already powers board.chat panels,
/// surfaced as a bottom-right slide-out drawer.
class YoloBadgeWithChat extends StatefulWidget {
  const YoloBadgeWithChat({super.key});

  @override
  State<YoloBadgeWithChat> createState() => _YoloBadgeWithChatState();
}

class _YoloBadgeWithChatState extends State<YoloBadgeWithChat> {
  bool _chatOpen = false;

  // In-memory panel instance that backs the floating chat drawer.
  BoardPanelInstance _badgePanel = const BoardPanelInstance(
    id: '__yolo_badge_assistant__',
    type: 'board.chat',
    title: 'YoLo Assistant',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 380, height: 480),
  );

  final ChatPanelController _chatControllerSurface = ChatPanelController();

  void _toggleChat() {
    setState(() => _chatOpen = !_chatOpen);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 540,
      child: YoloBadgeChatShell(
        isOpen: _chatOpen,
        onToggle: _toggleChat,
        panelContent: ChatPanelWidget(
          panel: _badgePanel,
          controller: _chatControllerSurface,
          onUpdateState: (newState) {
            setState(() {
              _badgePanel = _badgePanel.copyWith(state: newState);
            });
          },
        ),
      ),
    );
  }
}
