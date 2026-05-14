import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/runs/ui/run_panel.dart';

/// Board panel plugin that embeds the real shared Run panel.
///
/// This keeps board-run behavior aligned with the main Run view so commands
/// started from chat/CLI/UI all go through the same persistent backend.
class RunConfigsPlugin extends BoardPanelPlugin {
  const RunConfigsPlugin();

  static const String kTypeId = 'board.run_configs';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Run Configs';

  @override
  IconData get icon => Icons.play_circle_outline;

  @override
  Color get accentColor => const Color(0xFF22C55E);

  @override
  Size get defaultSize => const Size(600, 400);

  @override
  Map<String, dynamic> get initialState => const {};

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final stateGroup = panel.state['group'];
    final groupId = stateGroup is String && stateGroup.trim().isNotEmpty
        ? stateGroup.trim()
        : panel.id;
    final activeSessionId = panel.state['activeSessionId'] as String?;
    final hiddenSessionIds = _readHiddenSessionIds(panel);
    return RunPanel(
      groupId: groupId,
      initialAttachedSessionId: activeSessionId,
      hiddenSessionIds: hiddenSessionIds,
      onGroupChanged: (next) {
        renderContext.onUpdateState({
          ...panel.state,
          'group': next.trim(),
        });
      },
      onAttachedSessionChanged: (sessionId) {
        renderContext.onUpdateState({
          ...panel.state,
          'activeSessionId': sessionId,
        });
      },
      onSessionVisibilityChanged: (sessionId, hidden) {
        final nextHidden = <String>{...hiddenSessionIds};
        if (hidden) {
          nextHidden.add(sessionId);
        } else {
          nextHidden.remove(sessionId);
        }
        renderContext.onUpdateState({
          ...panel.state,
          'hiddenSessionIds': nextHidden.toList(),
        });
      },
      onDetachToPanel: (session) async {
        final createLinked = renderContext.onCreateLinkedPanel;
        if (createLinked == null) return;
        await createLinked(
          RunPlugin.kTypeId,
          {
            'group': session.config.group,
            'activeSessionId': session.id,
          },
          'Run: ${session.config.name}',
        );
      },
    );
  }
}

/// Board panel plugin with a single shared run scope (`default`) and no group UI.
class RunPlugin extends BoardPanelPlugin {
  const RunPlugin();

  static const String kTypeId = 'board.run';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Run';

  @override
  IconData get icon => Icons.play_arrow_rounded;

  @override
  Color get accentColor => const Color(0xFF22C55E);

  @override
  Size get defaultSize => const Size(560, 360);

  @override
  Map<String, dynamic> get initialState => const {
    'group': 'default',
    'activeSessionId': null,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final stateGroup = panel.state['group'];
    final groupId = stateGroup is String && stateGroup.trim().isNotEmpty
        ? stateGroup.trim()
        : 'default';
    final activeSessionId = panel.state['activeSessionId'] as String?;
    final hiddenSessionIds = _readHiddenSessionIds(panel);
    return RunPanel(
      groupId: groupId,
      showGroupControls: false,
      showConfigList: false,
      showSessionTabs: false,
      initialAttachedSessionId: activeSessionId,
      hiddenSessionIds: hiddenSessionIds,
      onGroupChanged: (next) {
        renderContext.onUpdateState({
          ...panel.state,
          'group': next.trim(),
        });
      },
      onAttachedSessionChanged: (sessionId) {
        renderContext.onUpdateState({
          ...panel.state,
          'group': groupId,
          'activeSessionId': sessionId,
        });
      },
      onSessionVisibilityChanged: (sessionId, hidden) {
        final nextHidden = <String>{...hiddenSessionIds};
        if (hidden) {
          nextHidden.add(sessionId);
        } else {
          nextHidden.remove(sessionId);
        }
        renderContext.onUpdateState({
          ...panel.state,
          'group': groupId,
          'activeSessionId': panel.state['activeSessionId'],
          'hiddenSessionIds': nextHidden.toList(),
        });
      },
      onSendToGroup: (session, group, createNewPanel) async {
        final findPanel = renderContext.onFindPanelByGroup;
        final revealSession = renderContext.onRevealSessionInPanel;
        final focusPanel = renderContext.onFocusPanelById;
        final createLinked = renderContext.onCreateLinkedPanel;

        if (!createNewPanel &&
            findPanel != null &&
            revealSession != null &&
            focusPanel != null) {
          final existingId = findPanel(RunConfigsPlugin.kTypeId, group);
          if (existingId != null) {
            await revealSession(existingId, session.id);
            await focusPanel(existingId);
            return;
          }
        }

        if (createLinked == null) return;
        await createLinked(
          RunConfigsPlugin.kTypeId,
          {
            'group': group,
            'activeSessionId': session.id,
          },
          'Run Configs: $group',
        );
      },
    );
  }
}

List<String> _readHiddenSessionIds(BoardPanelInstance panel) {
  final raw = panel.state['hiddenSessionIds'];
  if (raw is List) {
    return raw.whereType<String>().map((id) => id.trim()).toList();
  }
  return const [];
}
