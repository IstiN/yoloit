import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/ui/shell/main_shell.dart';
import 'package:yoloit/ui/widgets/panel_visibility.dart';

AgentSession _session(String id, {Map<String, String>? worktreeContexts}) {
  return AgentSession(
    id: id,
    type: AgentType.copilot,
    workspacePath: '/repo',
    worktreeContexts: worktreeContexts,
  );
}

void main() {
  group('toggledPanelVisibility', () {
    test('open toggles to closed', () {
      expect(
        toggledPanelVisibility(PanelVisibility.open),
        PanelVisibility.closed,
      );
    });

    test('closed toggles to open', () {
      expect(
        toggledPanelVisibility(PanelVisibility.closed),
        PanelVisibility.open,
      );
    });

    test('collapsed toggles to open', () {
      expect(
        toggledPanelVisibility(PanelVisibility.collapsed),
        PanelVisibility.open,
      );
    });
  });

  group('fourPaneAgentsSectionPresent', () {
    test('present when agents open', () {
      expect(fourPaneAgentsSectionPresent(true, false), isTrue);
    });

    test('present when agents collapsed into rail', () {
      expect(fourPaneAgentsSectionPresent(false, true), isTrue);
    });

    test('absent when fully closed', () {
      expect(fourPaneAgentsSectionPresent(false, false), isFalse);
    });
  });

  group('fourPaneShowsEmptyState', () {
    test('shows only when every pane is fully closed', () {
      expect(
        fourPaneShowsEmptyState(
          showAgents: false,
          agentsCollapsed: false,
          showEditor: false,
          showFileTree: false,
        ),
        isTrue,
      );
    });

    test('hidden when agents open', () {
      expect(
        fourPaneShowsEmptyState(
          showAgents: true,
          agentsCollapsed: false,
          showEditor: false,
          showFileTree: false,
        ),
        isFalse,
      );
    });

    test('hidden when agents collapsed (rail still visible)', () {
      expect(
        fourPaneShowsEmptyState(
          showAgents: false,
          agentsCollapsed: true,
          showEditor: false,
          showFileTree: false,
        ),
        isFalse,
      );
    });

    test('hidden when editor visible', () {
      expect(
        fourPaneShowsEmptyState(
          showAgents: false,
          agentsCollapsed: false,
          showEditor: true,
          showFileTree: false,
        ),
        isFalse,
      );
    });

    test('hidden when file tree visible', () {
      expect(
        fourPaneShowsEmptyState(
          showAgents: false,
          agentsCollapsed: false,
          showEditor: false,
          showFileTree: true,
        ),
        isFalse,
      );
    });
  });

  group('agentsWorkspaceListenWhen', () {
    const loaded = WorkspaceLoaded(
      workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
      activeWorkspaceId: 'ws-1',
    );

    test('ignores non-loaded current state', () {
      expect(
        agentsWorkspaceListenWhen(loaded, const WorkspaceLoading()),
        isFalse,
      );
    });

    test('fires on first loaded state', () {
      expect(
        agentsWorkspaceListenWhen(const WorkspaceInitial(), loaded),
        isTrue,
      );
    });

    test('fires when active workspace id changes', () {
      const next = WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-2', name: 'Two', paths: ['/b'])],
        activeWorkspaceId: 'ws-2',
      );
      expect(agentsWorkspaceListenWhen(loaded, next), isTrue);
    });

    test('does not fire when active workspace id is unchanged', () {
      expect(agentsWorkspaceListenWhen(loaded, loaded), isFalse);
    });

    test('does not fire when new active workspace id is null', () {
      const next = WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
      );
      expect(agentsWorkspaceListenWhen(loaded, next), isFalse);
    });
  });

  group('agentsSessionListenWhen', () {
    test('ignores non-loaded current state', () {
      expect(
        agentsSessionListenWhen(
          const TerminalInitial(),
          const TerminalInitial(),
        ),
        isFalse,
      );
    });

    test('fires on first loaded state', () {
      final loaded = TerminalLoaded(sessions: [_session('s1')], activeIndex: 0);
      expect(agentsSessionListenWhen(const TerminalInitial(), loaded), isTrue);
    });

    test('fires when active session id changes', () {
      final prev = TerminalLoaded(
        sessions: [_session('s1'), _session('s2')],
        activeIndex: 0,
      );
      final next = prev.copyWith(activeIndex: 1);
      expect(agentsSessionListenWhen(prev, next), isTrue);
    });

    test('does not fire when active session id is unchanged', () {
      final prev = TerminalLoaded(sessions: [_session('s1')], activeIndex: 0);
      final next = prev.copyWith();
      expect(agentsSessionListenWhen(prev, next), isFalse);
    });
  });

  group('resolveSessionPaths', () {
    test('prefers worktree context paths when set', () {
      final session = _session(
        's1',
        worktreeContexts: const {'/repo': '/repo/.worktrees/wt-1'},
      );
      const wsState = WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
        activeWorkspaceId: 'ws-1',
      );

      expect(
        resolveSessionPaths(wsState, session),
        ['/repo/.worktrees/wt-1'],
      );
    });

    test('falls back to active workspace paths without worktrees', () {
      const wsState = WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws-1', name: 'One', paths: ['/a']),
          Workspace(id: 'ws-2', name: 'Two', paths: ['/b', '/c']),
        ],
        activeWorkspaceId: 'ws-2',
      );

      expect(resolveSessionPaths(wsState, _session('s1')), ['/b', '/c']);
    });

    test('falls back to first workspace when active id is unknown', () {
      const wsState = WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
        activeWorkspaceId: 'missing',
      );

      expect(resolveSessionPaths(wsState, _session('s1')), ['/a']);
    });

    test('returns empty when no active workspace', () {
      const wsState = WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
      );

      expect(resolveSessionPaths(wsState, _session('s1')), isEmpty);
    });

    test('returns empty when workspaces not loaded', () {
      expect(
        resolveSessionPaths(const WorkspaceInitial(), _session('s1')),
        isEmpty,
      );
    });
  });

  group('resourceRamSharePercent', () {
    ResourceSnapshot snap({required int total, required int used}) {
      return ResourceSnapshot(
        appMemoryBytes: used,
        appCpuPercent: 0,
        sessions: const [],
        host: HostMetrics(
          totalBytes: total,
          freeBytes: total - used,
          usedBytes: used,
          usedPercent: total == 0 ? 0 : used / total * 100,
          cpuCoreCount: 8,
          loadAverage1m: 1,
        ),
        totalMemoryBytes: used,
        totalCpuPercent: 0,
      );
    }

    test('zero when host total is unknown', () {
      expect(resourceRamSharePercent(snap(total: 0, used: 0)), 0.0);
    });

    test('computes share of host memory', () {
      expect(resourceRamSharePercent(snap(total: 1000, used: 250)), 25.0);
    });

    test('clamps to 100', () {
      expect(resourceRamSharePercent(snap(total: 100, used: 500)), 100.0);
    });
  });

  group('resourceMemoryBarColor', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);

    test('error color at 90%+', () {
      expect(resourceMemoryBarColor(colors, 90), colors.statusError);
      expect(resourceMemoryBarColor(colors, 99), colors.statusError);
    });

    test('warning color between 70% and 90%', () {
      expect(resourceMemoryBarColor(colors, 70), colors.statusWarning);
      expect(resourceMemoryBarColor(colors, 89.9), colors.statusWarning);
    });

    test('primary color below 70%', () {
      expect(resourceMemoryBarColor(colors, 0), colors.primary);
      expect(resourceMemoryBarColor(colors, 69.9), colors.primary);
    });
  });

  group('window control button colors', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);
    const fallback = Colors.white;

    test('close button hover uses error color', () {
      expect(
        winBtnHoverColor(isClose: true, colors: colors),
        colors.statusError,
      );
    });

    test('other buttons hover uses muted wash', () {
      expect(
        winBtnHoverColor(isClose: false, colors: colors),
        colors.textMuted.withAlpha(40),
      );
    });

    test('icon highlighted only when close button hovered', () {
      expect(
        winBtnIconColor(
          hovered: true,
          isClose: true,
          colors: colors,
          fallbackColor: fallback,
        ),
        colors.textPrimary,
      );
      expect(
        winBtnIconColor(
          hovered: true,
          isClose: false,
          colors: colors,
          fallbackColor: fallback,
        ),
        fallback,
      );
      expect(
        winBtnIconColor(
          hovered: false,
          isClose: true,
          colors: colors,
          fallbackColor: fallback,
        ),
        fallback,
      );
    });
  });
}
