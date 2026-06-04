import 'package:flutter/material.dart';

import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/ui/widgets/ui_components.dart';

/// Pulsing badge that reflects a tool execution status.
class ChatToolStatusBadge extends StatelessWidget {
  const ChatToolStatusBadge({super.key, required this.status});

  final ToolExecutionStatus status;

  @override
  Widget build(BuildContext context) {
    return NeonBadge(
      label: status.label,
      color: status.tint,
      showPulse: status.isRunning,
    );
  }
}
