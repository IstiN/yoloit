import 'dart:io';

import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void registerChatProcessResource({
  required Process process,
  required String providerId,
  required ChatSessionConfig config,
  required ChatRuntimeContext? runtimeContext,
}) {
  final panelTitle = runtimeContext?.panelTitle?.trim();
  final sessionName = config.sessionName.trim();
  final labelTitle =
      panelTitle != null && panelTitle.isNotEmpty
          ? panelTitle
          : (sessionName.isNotEmpty ? sessionName : providerId);
  ResourceMonitorService.instance.registerSession(
    process.pid,
    'AI Chat · $labelTitle',
    metadata: ResourceSessionMetadata(
      kind: 'ai chat',
      boardId: runtimeContext?.boardId,
      boardName: runtimeContext?.boardName,
      panelId: runtimeContext?.panelId,
      panelTitle: labelTitle,
      panelType: runtimeContext?.panelType,
      workspacePath: config.workingDir.trim(),
      provider: providerId,
    ),
  );
}

void unregisterChatProcessResource(Process process) {
  ResourceMonitorService.instance.unregisterSession(process.pid);
}
