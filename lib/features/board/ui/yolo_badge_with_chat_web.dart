import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Web stub for [YoloBadgeWithChat].
///
/// The assistant widget pulls in native-only packages (`local_models_flutter`,
/// `record`, window management, etc.), so the full badge is disabled on web.
/// The public constructor is preserved so callers do not need conditional
/// imports.
class YoloBadgeWithChat extends StatefulWidget {
  const YoloBadgeWithChat();

  @override
  State<YoloBadgeWithChat> createState() => _YoloBadgeWithChatState();
}

class _YoloBadgeWithChatState extends State<YoloBadgeWithChat> {
  // In-memory panel instance kept for API parity with the VM version.
  final BoardPanelInstance _badgePanel = const BoardPanelInstance(
    id: '__yolo_badge_assistant__',
    type: 'board.yolo_assistant',
    title: 'YoLo Assistant',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 380, height: 480),
  );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
