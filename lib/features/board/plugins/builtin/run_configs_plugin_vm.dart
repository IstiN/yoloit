import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/run_configs_plugin_base.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/runs/ui/run_panel.dart';

class RunConfigsPlugin extends RunConfigsPluginBase {
  const RunConfigsPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _RunPluginBody(
      panel: panel,
      renderContext: renderContext,
      fallbackGroupId: panel.id,
    );
  }
}

class RunPlugin extends RunPluginBase {
  const RunPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _RunPluginBody(
      panel: panel,
      renderContext: renderContext,
      fallbackGroupId: 'default',
      showGroupControls: false,
      showConfigList: false,
      showSessionTabs: false,
      onSendToGroup: (session, group, createNewPanel) async {
        final findPanel = renderContext.onFindPanelByGroup;
        final revealSession = renderContext.onRevealSessionInPanel;
        final focusPanel = renderContext.onFocusPanelById;
        final createLinked = renderContext.onCreateLinkedPanel;

        if (!createNewPanel &&
            findPanel != null &&
            revealSession != null &&
            focusPanel != null) {
          final existingId = findPanel(RunConfigsPluginBase.kTypeId, group);
          if (existingId != null) {
            await revealSession(existingId, session.id);
            await focusPanel(existingId);
            return;
          }
        }

        if (createLinked == null) return;
        await createLinked(RunConfigsPluginBase.kTypeId, {
          'group': group,
          'activeSessionId': session.id,
        }, 'Run Configs: $group');
      },
    );
  }
}

class _RunPluginBody extends StatelessWidget {
  const _RunPluginBody({
    required this.panel,
    required this.renderContext,
    required this.fallbackGroupId,
    this.showGroupControls = true,
    this.showConfigList = true,
    this.showSessionTabs = true,
    this.onSendToGroup,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  final String fallbackGroupId;
  final bool showGroupControls;
  final bool showConfigList;
  final bool showSessionTabs;
  final RunPanelSendToGroupCallback? onSendToGroup;

  @override
  Widget build(BuildContext context) {
    final stateGroup = panel.state['group'];
    final groupId =
        stateGroup is String && stateGroup.trim().isNotEmpty
            ? stateGroup.trim()
            : fallbackGroupId;
    final activeSessionId = panel.state['activeSessionId'] as String?;
    final hiddenSessionIds = _readHiddenSessionIds(panel);

    return ScrollableCardMarker(
      child: ScrollableCardRegion(
        child: RunPanel(
          groupId: groupId,
          showGroupControls: showGroupControls,
          showConfigList: showConfigList,
          showSessionTabs: showSessionTabs,
          initialAttachedSessionId: activeSessionId,
          hiddenSessionIds: hiddenSessionIds,
          onGroupChanged: (next) {
            renderContext.onUpdateState({...panel.state, 'group': next.trim()});
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
            await createLinked(RunPluginBase.kTypeId, {
              'group': session.config.group,
              'activeSessionId': session.id,
            }, 'Run: ${session.config.name}');
          },
          onSendToGroup: onSendToGroup,
        ),
      ),
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
