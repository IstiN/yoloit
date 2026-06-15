import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

/// Slash command definition for the chat input bar.
class ChatSlashCommand {
  const ChatSlashCommand({
    required this.id,
    required this.displayName,
    required this.description,
    required this.triggers,
  });

  final String id;
  final String displayName;
  final String description;
  final List<String> triggers;

  bool matches(String text) => triggers.any(text.startsWith);
}

List<(String, String)> buildChatProviderOptions(Iterable<AgentConfig> configs) {
  final byId = <String, String>{};
  for (final cfg in configs) {
    if (cfg.streamAdapter == null || !cfg.visible) continue;
    byId[cfg.id] = cfg.displayName;
  }
  return byId.entries.map((e) => (e.key, e.value)).toList();
}

String? resolveChatProviderSelection(
  String selectedProvider,
  List<(String, String)> providers,
) {
  if (providers.any((p) => p.$1 == selectedProvider)) {
    return selectedProvider;
  }
  return providers.firstOrNull?.$1;
}

/// Status metadata for a tool execution badge.
class ToolExecutionStatus {
  const ToolExecutionStatus({
    required this.icon,
    required this.label,
    required this.tint,
    this.isRunning = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool isRunning;

  factory ToolExecutionStatus.from(
    AppColorScheme colors, {
    required bool? success,
    required String content,
  }) {
    final exitCode = extractExitCode(content);
    if (success == null) {
      if (exitCode != null) {
        return ToolExecutionStatus(
          icon:
              exitCode == 0 ? Icons.check_circle_rounded : Icons.error_rounded,
          label: exitCode == 0 ? 'Done $exitCode' : 'Failed $exitCode',
          tint: exitCode == 0 ? colors.statusActive : colors.statusError,
        );
      }
      if (content.trim().isNotEmpty) {
        return ToolExecutionStatus(
          icon: Icons.check_circle_rounded,
          label: 'Done',
          tint: colors.statusActive,
        );
      }
      return ToolExecutionStatus(
        icon: Icons.pending_outlined,
        label: 'Running',
        tint: colors.statusWarning,
        isRunning: true,
      );
    }
    if (success) {
      return ToolExecutionStatus(
        icon: Icons.check_circle_rounded,
        label: exitCode == null ? 'Done' : 'Done $exitCode',
        tint: colors.statusActive,
      );
    }
    return ToolExecutionStatus(
      icon: Icons.error_rounded,
      label: exitCode == null ? 'Failed' : 'Failed $exitCode',
      tint: colors.statusError,
    );
  }
}

/// Extracts an exit code from tool-result text.
int? extractExitCode(String content) {
  final match = RegExp(
    r'(?:exited with exit code|exit code)\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(content);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Returns a one-line preview of tool output (strips HTML, picks first line).
String? toolResultPreview(String content) {
  final cleaned =
      content
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .where(
            (line) => !line.toLowerCase().contains('exited with exit code'),
          )
          .toList();
  if (cleaned.isEmpty) {
    final exitCode = extractExitCode(content);
    return exitCode == null ? null : 'Exited with code $exitCode';
  }
  return cleaned.first;
}

/// Event emitted during a sub-agent run.
class SubAgentEvent {
  SubAgentEvent({
    required this.type,
    required this.timestamp,
    this.toolName,
    this.content,
  });

  /// One of: 'tool_start', 'tool_complete', 'tool_error', 'message'
  final String type;
  final DateTime timestamp;
  final String? toolName;
  final String? content;
}

/// Mutable state for a single sub-agent execution.
class SubAgentRunState {
  SubAgentRunState({
    required this.agentId,
    required this.agentName,
    required this.agentDescription,
  });

  final String agentId;
  final String agentName;
  final String agentDescription;
  final List<SubAgentEvent> events = [];
  bool isRunning = true;
}
