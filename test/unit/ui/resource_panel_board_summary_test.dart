import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/ui/shell/main_shell.dart';

void main() {
  test('resourcePanelTypeCounts sorts panel types by count then label', () {
    final counts = resourcePanelTypeCounts([
      BoardPanelInstance(
        id: 'terminal-1',
        type: 'board.terminal',
        title: 'Terminal',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
      BoardPanelInstance(
        id: 'sticky-1',
        type: 'board.sticky',
        title: 'Sticky',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
      BoardPanelInstance(
        id: 'terminal-2',
        type: 'board.terminal',
        title: 'Terminal 2',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
    ]);

    expect(counts.keys.first, 'board.terminal');
    expect(counts['board.terminal'], 2);
    expect(counts['board.sticky'], 1);
  });

  test('resourcePanelTypeLabel uses plugin names with readable fallback', () {
    expect(resourcePanelTypeLabel('board.terminal'), 'Terminal');
    expect(resourcePanelTypeLabel('board.custom_unknown'), 'custom unknown');
  });

  test('resource session metadata builds panel-aware labels', () {
    const metadata = ResourceSessionMetadata(
      kind: 'ai chat',
      boardId: 'board-1',
      boardName: 'Work',
      panelId: 'panel-1',
      panelTitle: 'Release helper',
      panelType: 'board.chat',
      workspacePath: '/repo',
      provider: 'copilot',
    );

    expect(metadata.displayLabel, 'AI Chat · Work · Release helper');
  });

  test('displayLabel uses board without panel title', () {
    const meta = ResourceSessionMetadata(
      kind: 'terminal',
      boardName: 'Dev Board',
    );
    expect(meta.displayLabel, 'Terminal · Dev Board');
  });

  test('enrichResourceSessionFromBoards links yoloitd session to terminal panel', () {
    const session = SessionStat(
      pid: 42,
      label: 'Board Terminal',
      cpuPercent: 1,
      memoryBytes: 100,
      sessionKey: 'board_terminal_99',
    );
    final boards = [
      BoardDocument(
        id: 'board-1',
        name: 'My Test Board',
        panels: [
          BoardPanelInstance(
            id: 'panel-terminal-1',
            type: 'board.terminal',
            title: 'Release shell',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
            state: {
              'config': {
                'sessionId': 'board_terminal_99',
                'sessionName': 'release',
                'workingDir': '/tmp/repo',
                'envGroupIds': <String>[],
              },
            },
          ),
        ],
      ),
    ];

    final enriched = enrichResourceSessionFromBoards(session, boards);
    expect(enriched.metadata?.panelId, 'panel-terminal-1');
    expect(enriched.metadata?.boardId, 'board-1');
    expect(enriched.metadata?.displayLabel, 'Terminal · My Test Board · Release shell');
  });

  test('shouldShowYoloitResourceSession hides unlinked terminals in yoloit only', () {
    const linked = SessionStat(
      pid: 1,
      label: 'terminal',
      cpuPercent: 0,
      memoryBytes: 0,
      metadata: ResourceSessionMetadata(
        kind: 'terminal',
        panelId: 'panel-1',
      ),
    );
    const orphan = SessionStat(
      pid: 2,
      label: 'board_terminal_old',
      cpuPercent: 0,
      memoryBytes: 0,
    );

    expect(
      shouldShowYoloitResourceSession(linked, ResourceMonitorScope.yoloitOnly),
      isTrue,
    );
    expect(
      shouldShowYoloitResourceSession(orphan, ResourceMonitorScope.yoloitOnly),
      isFalse,
    );
    expect(
      shouldShowYoloitResourceSession(orphan, ResourceMonitorScope.allAgents),
      isTrue,
    );
  });

  test('enrichResourceSessionFromBoards uses persisted runtime metadata', () {
    ResourceMonitorService.instance.registerRuntimeSession(
      'board_terminal_77',
      'Shell',
      metadata: const ResourceSessionMetadata(
        kind: 'terminal',
        boardId: 'board-1',
        boardName: 'Work',
        panelId: 'panel-1',
        panelTitle: 'Shell',
        panelType: 'board.terminal',
        provider: 'terminal',
      ),
    );

    const session = SessionStat(
      pid: 42,
      label: 'Shell',
      cpuPercent: 1,
      memoryBytes: 100,
      sessionKey: 'board_terminal_77',
    );

    final enriched = enrichResourceSessionFromBoards(session, const []);
    expect(enriched.metadata?.panelId, 'panel-1');
    expect(
      shouldShowYoloitResourceSession(
        enriched,
        ResourceMonitorScope.yoloitOnly,
      ),
      isTrue,
    );

    ResourceMonitorService.instance.unregisterRuntimeSession('board_terminal_77');
  });

  test('resourceSessionCanStop allows AI/tool sessions but not terminals', () {
    const aiSession = SessionStat(
      pid: 10,
      label: 'AI Chat',
      cpuPercent: 0,
      memoryBytes: 0,
      metadata: ResourceSessionMetadata(kind: 'ai chat'),
    );
    const terminalSession = SessionStat(
      pid: 11,
      label: 'Terminal',
      cpuPercent: 0,
      memoryBytes: 0,
      metadata: ResourceSessionMetadata(kind: 'terminal'),
    );
    const detachedCopilot = SessionStat(
      pid: 12,
      label: 'copilot',
      cpuPercent: 0,
      memoryBytes: 0,
    );

    expect(resourceSessionCanStop(aiSession), isTrue);
    expect(resourceSessionCanStop(detachedCopilot), isTrue);
    expect(resourceSessionCanStop(terminalSession), isFalse);
  });
}
