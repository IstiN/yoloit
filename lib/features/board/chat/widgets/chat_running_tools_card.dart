import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Card showing currently running tool calls (including sub-agents).
class ChatRunningToolsCard extends StatelessWidget {
  const ChatRunningToolsCard({
    required this.tools,
    required this.subAgents,
    required this.subAgentPanels,
    required this.isSubAgentToolCall,
    required this.onFocusPanel,
    super.key,
  });

  final List<ChatToolCall> tools;
  final Map<String, SubAgentRunState> subAgents;
  final Map<String, String> subAgentPanels;
  final bool Function(String) isSubAgentToolCall;
  final void Function(String) onFocusPanel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            tools.map((tool) {
              final isAgent = isSubAgentToolCall(tool.toolName);
              final agentDesc =
                  (tool.arguments['description'] as String?)?.trim() ??
                  (tool.arguments['name'] as String?)?.trim();
              final color =
                  isAgent ? colors.primaryLight : colors.accentOrange;
              final subAgent = isAgent ? subAgents[tool.toolCallId] : null;
              final panelId = isAgent ? subAgentPanels[tool.toolCallId] : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isAgent ? Icons.smart_toy_outlined : Icons.build_outlined,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isAgent
                                ? (subAgent != null
                                    ? subAgent.agentName
                                    : 'Running sub-agent\u2026')
                                : tool.toolName,
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isAgent && agentDesc != null)
                            Text(
                              agentDesc,
                              style: TextStyle(
                                fontSize: 11,
                                color: color.withAlpha(180),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (subAgent != null && subAgent.events.isNotEmpty)
                            Text(
                              '${subAgent.events.length} events',
                              style: TextStyle(
                                fontSize: 10,
                                color: color.withAlpha(140),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (panelId != null)
                      GestureDetector(
                        onTap: () => onFocusPanel(panelId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: color.withAlpha(80)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(Icons.open_in_new, size: 10, color: color),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }
}
