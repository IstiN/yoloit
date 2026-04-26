import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/sidebar/show_hide_sidebar.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

const _surfaceBg = Color(0xFF0D1117);

MindMapState _buildSidebarState() {
  const workspaceId = 'ws:alpha';
  const agentNodeId = 'agent:alpha';
  const sessionNodeId = 'session:alpha';
  const repoNodeId = 'repo:alpha';
  const branchNodeId = 'branch:alpha';
  const treeNodeId = 'tree:alpha';
  const diffNodeId = 'diff:alpha';
  const runNodeId = 'run:alpha';
  const editorNodeId = 'editor:notes';

  final workspace = Workspace(
    id: 'alpha',
    name: 'Alpha Workspace',
    paths: const ['/tmp/alpha'],
    color: const Color(0xFF7C6BFF),
  );
  final agentSession = AgentSession(
    id: 'agent-session-alpha',
    type: AgentType.copilot,
    workspacePath: '/tmp/alpha',
    status: AgentStatus.live,
    customName: 'Copilot Session',
  );
  final shellSession = AgentSession(
    id: 'shell-session-alpha',
    type: AgentType.terminal,
    workspacePath: '/tmp/alpha',
    customName: 'Shell Session',
  );
  final runSession = RunSession(
    id: 'run-session-alpha',
    config: const RunConfig(
      id: 'run-config-alpha',
      name: 'flutter test',
      command: 'flutter test',
    ),
    workspacePath: '/tmp/alpha',
    status: RunStatus.running,
  );

  return MindMapState(
    positions: const {
      workspaceId: Offset(0, 0),
      agentNodeId: Offset(240, 0),
      sessionNodeId: Offset(240, 160),
      repoNodeId: Offset(520, 0),
      branchNodeId: Offset(720, 0),
      treeNodeId: Offset(520, 180),
      diffNodeId: Offset(720, 180),
      runNodeId: Offset(520, 360),
      editorNodeId: Offset(0, 360),
    },
    hidden: const {editorNodeId},
    hiddenTypes: const {'diff'},
    nodes: [
      WorkspaceNodeData(id: workspaceId, workspace: workspace),
      AgentNodeData(
        id: agentNodeId,
        session: agentSession,
        workspaceId: workspaceId,
      ),
      SessionNodeData(
        id: sessionNodeId,
        workspaceId: workspaceId,
        session: shellSession,
      ),
      RepoNodeData(
        id: repoNodeId,
        sessionId: agentNodeId,
        repoPath: '/tmp/alpha/yoloit',
        repoName: 'alpha-repo',
        branch: 'main',
      ),
      BranchNodeData(
        id: branchNodeId,
        repoId: repoNodeId,
        repoName: 'alpha-repo',
        branch: 'main',
        commitHash: 'abcdef1',
      ),
      FileTreeNodeData(
        id: treeNodeId,
        workspaceId: workspaceId,
        repoPath: '/tmp/alpha/yoloit',
        repoName: 'File Tree',
      ),
      DiffNodeData(
        id: diffNodeId,
        workspaceId: workspaceId,
        repoPath: '/tmp/alpha/yoloit',
        repoName: 'Diff View',
      ),
      RunNodeData(id: runNodeId, session: runSession, workspaceId: workspaceId),
      const EditorNodeData(
        id: editorNodeId,
        filePath: '/tmp/alpha/notes/todo.dart',
        content: 'void main() {}\n',
        language: 'dart',
      ),
    ],
    connections: const [
      MindMapConnection(
        fromId: workspaceId,
        toId: agentNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFF7C6BFF),
      ),
      MindMapConnection(
        fromId: workspaceId,
        toId: sessionNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFF7C6BFF),
      ),
      MindMapConnection(
        fromId: workspaceId,
        toId: treeNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFF7C6BFF),
      ),
      MindMapConnection(
        fromId: workspaceId,
        toId: diffNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFF7C6BFF),
      ),
      MindMapConnection(
        fromId: agentNodeId,
        toId: repoNodeId,
        style: ConnectorStyle.animated,
        color: Color(0xFF34D399),
      ),
      MindMapConnection(
        fromId: repoNodeId,
        toId: branchNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFF60A5FA),
      ),
      MindMapConnection(
        fromId: agentNodeId,
        toId: runNodeId,
        style: ConnectorStyle.solid,
        color: Color(0xFFFF6B6B),
      ),
    ],
  );
}

Map<String, List<double>> _positionsFromPayload(Map<String, dynamic> payload) {
  final positions = Map<String, dynamic>.from(payload['positions'] as Map);
  return positions.map(
    (key, value) => MapEntry(
      key,
      (value as List).map((entry) => (entry as num).toDouble()).toList(),
    ),
  );
}

Map<String, Map<String, dynamic>> _nodeContentFromPayload(
  Map<String, dynamic> payload,
) {
  final nodeContent = Map<String, dynamic>.from(payload['nodeContent'] as Map);
  return nodeContent.map(
    (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
  );
}

Future<void> _pumpSidebar(WidgetTester tester, ShowHideSidebarData data) async {
  tester.view.physicalSize = const Size(320, 520);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());

  await tester.pumpWidget(
    BlocProvider<ReviewCubit>(
      create: (_) => ReviewCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: _surfaceBg),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 520,
              child: MindMapShowHideSidebar(
                data: data,
                onToggleHide: (_) {},
                onToggleGroup: (_) {},
                onFocusNode: (_) {},
                onShowAll: () {},
                onHideAll: () {},
                onToggleType: (_) {},
                onCreateWorkspace: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _expandNestedTree(WidgetTester tester) async {
  await tester.tap(find.text('Copilot Session'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('alpha-repo'));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  group('show/hide sidebar parity', () {
    test('desktop state and snapshot payload build identical sidebar data', () {
      final state = _buildSidebarState();
      final desktopData = buildShowHideSidebarDataFromMindMapState(state);
      final payload = buildShowHideSidebarSnapshotPayloadFromMindMapState(
        state,
      );
      final snapshotMessage = SyncMessage.snapshot(
        positions: _positionsFromPayload(payload),
        sizes: const {},
        hidden: List<String>.from(payload['hidden'] as List),
        hiddenTypes: List<String>.from(payload['hiddenTypes'] as List),
        connections: (payload['connections'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList(),
        nodeContent: _nodeContentFromPayload(payload),
      );
      final decoded = SyncMessage.decode(snapshotMessage.encode());

      expect(decoded, isNotNull);
      expect(
        buildShowHideSidebarDataFromSnapshotPayload(decoded!.payload),
        desktopData,
      );
    });

    testWidgets('desktop-state sidebar matches golden', (tester) async {
      final data = buildShowHideSidebarDataFromMindMapState(
        _buildSidebarState(),
      );

      await _pumpSidebar(tester, data);
      await _expandNestedTree(tester);
      await _golden(tester, 'show_hide_sidebar');
    });

    testWidgets('snapshot sidebar matches desktop golden', (tester) async {
      final state = _buildSidebarState();
      final payload = buildShowHideSidebarSnapshotPayloadFromMindMapState(
        state,
      );
      final snapshotMessage = SyncMessage.snapshot(
        positions: _positionsFromPayload(payload),
        sizes: const {},
        hidden: List<String>.from(payload['hidden'] as List),
        hiddenTypes: List<String>.from(payload['hiddenTypes'] as List),
        connections: (payload['connections'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList(),
        nodeContent: _nodeContentFromPayload(payload),
      );
      final decoded = SyncMessage.decode(snapshotMessage.encode());

      expect(decoded, isNotNull);

      await _pumpSidebar(
        tester,
        buildShowHideSidebarDataFromSnapshotPayload(decoded!.payload),
      );
      await _expandNestedTree(tester);
      await _golden(tester, 'show_hide_sidebar');
    });
  });
}
