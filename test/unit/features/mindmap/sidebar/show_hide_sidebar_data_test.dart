import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/sidebar/show_hide_sidebar.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

Workspace _workspace(String id, String name) =>
    Workspace(id: id, name: name, paths: const ['/tmp/ws'], color: const Color(0xFF7C6BFF));

AgentSession _agentSession(String id, String name, {AgentStatus? status}) =>
    AgentSession(
      id: id,
      type: AgentType.copilot,
      workspacePath: '/tmp/ws',
      customName: name,
      status: status ?? AgentStatus.idle,
    );

RunSession _runSession(String name) => RunSession(
  id: 'run-$name',
  config: RunConfig(id: 'cfg-$name', name: name, command: 'echo $name'),
  workspacePath: '/tmp/ws',
  status: RunStatus.running,
);

/// One node of every [MindMapNodeData] subtype, all unreachable from any
/// workspace so they surface as orphans.
List<MindMapNodeData> _allNodeTypes() => [
  SessionNodeData(
    id: 'session:1',
    workspaceId: 'ws:1',
    session: _agentSession('shell-1', 'Shell Session'),
  ),
  const RepoNodeData(
    id: 'repo:1',
    sessionId: 'agent:1',
    repoPath: '/tmp/ws/repo',
    repoName: 'repo-name',
    branch: 'main',
  ),
  const BranchNodeData(
    id: 'branch:1',
    repoId: 'repo:1',
    repoName: 'repo-name',
    branch: 'feature/x',
    commitHash: 'abc1234',
  ),
  const FilesNodeData(
    id: 'files:1',
    sessionId: 'agent:1',
    repoPath: '/tmp/ws/repo',
    changedFiles: [],
  ),
  const FileTreeNodeData(id: 'tree:1', workspaceId: 'ws:1'),
  const DiffNodeData(id: 'diff:1', workspaceId: 'ws:1'),
  const EditorNodeData(
    id: 'editor:1',
    filePath: '/tmp/ws/notes/todo.dart',
    content: 'void main() {}',
    language: 'dart',
  ),
  const FilePanelNodeData(id: 'panel:1', filePath: '/tmp/ws/readme.md'),
  const FileDiffPanelNodeData(
    id: 'filediff:1',
    filePath: '/tmp/ws/lib/a.dart',
    repoPath: '/tmp/ws',
  ),
  RunNodeData(id: 'run:1', session: _runSession('flutter test'), workspaceId: 'ws:1'),
  const MindMapPluginNodeData(
    id: 'plugin:1',
    pluginId: 'com.example.clock',
    columnIndex: 9,
    typeTag: 'plugin',
    defaultSize: Size(200, 100),
  ),
];

void main() {
  group('buildShowHideSidebarDataFromMindMapState', () {
    test('maps every node subtype to its sidebar type and label', () {
      final state = MindMapState(nodes: _allNodeTypes());
      final data = buildShowHideSidebarDataFromMindMapState(state);

      final byType = {for (final node in data.orphans) node.type: node};
      expect(byType['session']!.label, 'Shell Session');
      expect(byType['repo']!.label, 'repo-name');
      expect(byType['branch']!.label, 'feature/x');
      expect(byType['files']!.label, 'repo');
      expect(byType['tree']!.label, 'Tree'); // repoName fallback
      expect(byType['diff']!.label, 'Diff'); // repoName fallback
      expect(byType['editor']!.label, 'todo.dart');
      expect(byType['panel']!.label, 'readme.md');
      expect(byType['filediff']!.label, 'a.dart');
      expect(byType['run']!.label, 'flutter test');
      expect(byType['plugin']!.label, 'plugin:1'); // label is the node id
    });

    test('workspace tree collects children recursively and skips orphans', () {
      final state = MindMapState(
        nodes: [
          WorkspaceNodeData(id: 'ws:1', workspace: _workspace('1', 'Main')),
          AgentNodeData(
            id: 'agent:1',
            session: _agentSession('s1', 'Agent One'),
            workspaceId: 'ws:1',
          ),
          const RepoNodeData(
            id: 'repo:1',
            sessionId: 'agent:1',
            repoPath: '/tmp/ws/repo',
            repoName: 'inner-repo',
            branch: 'main',
          ),
          // Unreachable node -> orphan.
          const EditorNodeData(
            id: 'editor:loose',
            filePath: '/tmp/ws/loose.txt',
            content: '',
            language: 'text',
          ),
        ],
        connections: const [
          MindMapConnection(
            fromId: 'ws:1',
            toId: 'agent:1',
            style: ConnectorStyle.solid,
            color: Color(0xFF000000),
          ),
          MindMapConnection(
            fromId: 'agent:1',
            toId: 'repo:1',
            style: ConnectorStyle.solid,
            color: Color(0xFF000000),
          ),
        ],
      );

      final data = buildShowHideSidebarDataFromMindMapState(state);
      expect(data.workspaces, hasLength(1));
      final workspace = data.workspaces.single;
      expect(workspace.type, 'workspace');
      expect(workspace.label, 'Main');
      expect(workspace.path, '/tmp/ws');
      expect(workspace.children.single.id, 'agent:1');
      expect(workspace.children.single.children.single.id, 'repo:1');
      expect(data.orphans.map((n) => n.id), ['editor:loose']);
    });

    test('hidden ids and hidden type tags mark nodes hidden', () {
      final state = MindMapState(
        hidden: const {'editor:1'},
        hiddenTypes: const {'diff'},
        nodes: _allNodeTypes(),
      );
      final data = buildShowHideSidebarDataFromMindMapState(state);
      final byId = {for (final node in data.orphans) node.id: node};

      expect(byId['editor:1']!.hidden, isTrue);
      expect(byId['diff:1']!.hidden, isTrue);
      expect(byId['repo:1']!.hidden, isFalse);
      expect(data.hiddenCount, 2);
      expect(data.hiddenTypes, {'diff'});
    });

    test('connection cycles terminate without duplicating nodes', () {
      final state = MindMapState(
        nodes: [
          WorkspaceNodeData(id: 'ws:1', workspace: _workspace('1', 'Main')),
          const RepoNodeData(
            id: 'repo:1',
            sessionId: 'agent:1',
            repoPath: '/tmp/ws/repo',
            repoName: 'repo',
            branch: 'main',
          ),
        ],
        connections: const [
          MindMapConnection(
            fromId: 'ws:1',
            toId: 'repo:1',
            style: ConnectorStyle.solid,
            color: Color(0xFF000000),
          ),
          // Cycle back into the workspace.
          MindMapConnection(
            fromId: 'repo:1',
            toId: 'ws:1',
            style: ConnectorStyle.solid,
            color: Color(0xFF000000),
          ),
        ],
      );

      final data = buildShowHideSidebarDataFromMindMapState(state);
      expect(data.workspaces, hasLength(1));
      final repo = data.workspaces.single.children.single;
      expect(repo.id, 'repo:1');
      // The cycle edge cannot re-enter the already-visited workspace.
      expect(repo.children, isEmpty);
      expect(data.orphans, isEmpty);
    });

    test('dangling connection targets are skipped', () {
      final state = MindMapState(
        nodes: [WorkspaceNodeData(id: 'ws:1', workspace: _workspace('1', 'Main'))],
        connections: const [
          MindMapConnection(
            fromId: 'ws:1',
            toId: 'missing:node',
            style: ConnectorStyle.solid,
            color: Color(0xFF000000),
          ),
        ],
      );

      final data = buildShowHideSidebarDataFromMindMapState(state);
      expect(data.workspaces.single.children, isEmpty);
    });
  });

  group('buildShowHideSidebarSnapshotPayloadFromMindMapState', () {
    test('derives node content from node data when nodeContent is empty', () {
      final state = MindMapState(
        positions: const {'ws:1': Offset(3, 4)},
        nodes: [
          WorkspaceNodeData(id: 'ws:1', workspace: _workspace('1', 'Main')),
          ..._allNodeTypes(),
        ],
      );

      final payload = buildShowHideSidebarSnapshotPayloadFromMindMapState(state);
      expect(payload['positions'], {
        'ws:1': [3.0, 4.0],
      });

      final content = payload['nodeContent']! as Map<String, dynamic>;
      expect(content['ws:1'], {
        'type': 'workspace',
        'name': 'Main',
        'path': '/tmp/ws',
      });
      expect(content['session:1'], {
        'type': 'session',
        'name': 'Shell Session',
      });
      expect(content['repo:1'], {
        'type': 'repo',
        'name': 'repo-name',
        'path': '/tmp/ws/repo',
        'branch': 'main',
      });
      expect(content['branch:1'], {
        'type': 'branch',
        'name': 'feature/x',
        'branch': 'feature/x',
      });
      expect(content['files:1'], {'type': 'files', 'repoPath': '/tmp/ws/repo'});
      expect(content['tree:1'], {
        'type': 'tree',
        'repoName': null,
        'repoPath': null,
      });
      expect(content['editor:1'], {
        'type': 'editor',
        'filePath': '/tmp/ws/notes/todo.dart',
      });
      expect(content['panel:1'], {
        'type': 'panel',
        'filePath': '/tmp/ws/readme.md',
      });
      expect(content['filediff:1'], {
        'type': 'filediff',
        'filePath': '/tmp/ws/lib/a.dart',
        'repoPath': '/tmp/ws',
      });
      expect(content['run:1'], {'type': 'run', 'name': 'flutter test'});
      expect(content['plugin:1'], {
        'type': 'plugin',
        'pluginId': 'com.example.clock',
        'name': 'plugin:1',
      });
      expect(
        (content['agent'] as Map?)?['status'],
        isNull,
        reason: 'no AgentNodeData in this state',
      );
    });

    test('agent node snapshot includes live/idle status', () {
      final state = MindMapState(
        nodes: [
          AgentNodeData(
            id: 'agent:1',
            session: _agentSession('s1', 'Live Agent', status: AgentStatus.live),
            workspaceId: 'ws:1',
          ),
        ],
      );
      final payload = buildShowHideSidebarSnapshotPayloadFromMindMapState(state);
      final content = payload['nodeContent']! as Map<String, dynamic>;
      expect(content['agent:1'], {
        'type': 'agent',
        'name': 'Live Agent',
        'status': 'live',
      });
    });

    test('prefers provided nodeContent over node-derived content', () {
      final state = MindMapState(
        nodes: [WorkspaceNodeData(id: 'ws:1', workspace: _workspace('1', 'Main'))],
        nodeContent: const {
          'ws:1': {'type': 'workspace', 'name': 'From Host'},
        },
      );

      final payload = buildShowHideSidebarSnapshotPayloadFromMindMapState(state);
      final content = payload['nodeContent']! as Map<String, dynamic>;
      final wsContent = Map<String, dynamic>.from(content['ws:1']! as Map);
      expect(wsContent['name'], 'From Host');
    });
  });

  group('buildShowHideSidebarDataFromSnapshotPayload', () {
    test('tolerates an empty payload', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {});
      expect(data.workspaces, isEmpty);
      expect(data.orphans, isEmpty);
      expect(data.hiddenCount, 0);
    });

    test('ignores connections with missing endpoints', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'ws:1': [0, 0],
          'repo:1': [10, 10],
        },
        'connections': [
          {'from': 'ws:1'},
          {'to': 'repo:1'},
          {'from': '', 'to': 'repo:1'},
        ],
      });

      expect(data.workspaces.single.id, 'ws:1');
      expect(data.workspaces.single.children, isEmpty);
      expect(data.orphans.map((n) => n.id), ['repo:1']);
    });

    test('derives types from id prefixes when content has no explicit type', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'ws:9': [0, 0],
          'repo:2': [10, 0],
          'bare-id': [20, 0],
        },
      });

      expect(data.workspaces.single.type, 'workspace');
      final orphanTypes = {for (final node in data.orphans) node.id: node.type};
      expect(orphanTypes['repo:2'], 'repo');
      expect(orphanTypes['bare-id'], 'bare-id'); // no colon -> id itself
    });

    test('derives fallback labels per type', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'a': [0, 0],
          'b': [0, 0],
          'c': [0, 0],
          'd': [0, 0],
          'e': [0, 0],
          'f': [0, 0],
          'g': [0, 0],
          'h': [0, 0],
          'i': [0, 0],
          'j': [0, 0],
          'k': [0, 0],
          'l': [0, 0],
          'm': [0, 0],
          'n': [0, 0],
          'o': [0, 0],
        },
        'nodeContent': {
          'a': {'type': 'workspace', 'path': '/x/alpha'},
          'b': {'type': 'workspace'},
          'c': {'type': 'repo', 'path': '/x/beta'},
          'd': {'type': 'repo'},
          'e': {'type': 'branch', 'branch': 'main'},
          'f': {'type': 'branch'},
          'g': {'type': 'files', 'repoPath': '/x/gamma'},
          'h': {'type': 'tree', 'repoPath': '/x/delta'},
          'i': {'type': 'diff', 'repoName': 'Named Diff'},
          'j': {'type': 'editor', 'filePath': '/x/file.dart'},
          'k': {'type': 'run'},
          'l': {'type': 'agent'},
          'm': {'type': 'session'},
          'n': {'type': 'plugin', 'pluginId': 'com.example.x'},
          'o': {'type': 'mystery'},
        },
      });

      final byId = {
        for (final node in [...data.workspaces, ...data.orphans]) node.id: node.label,
      };
      expect(byId['a'], 'alpha');
      expect(byId['b'], 'Workspace');
      expect(byId['c'], 'beta');
      expect(byId['d'], 'Repository');
      expect(byId['e'], 'main');
      expect(byId['f'], 'Branch');
      expect(byId['g'], 'gamma');
      expect(byId['h'], 'delta');
      expect(byId['i'], 'Named Diff');
      expect(byId['j'], 'file.dart');
      expect(byId['k'], 'Run');
      expect(byId['l'], 'Terminal');
      expect(byId['m'], 'Session');
      expect(byId['n'], 'com.example.x');
    });

    test('explicit name wins over type fallbacks', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'ws:1': [0, 0],
        },
        'nodeContent': {
          'ws:1': {'type': 'workspace', 'name': 'Custom Name', 'path': '/x/y'},
        },
      });
      expect(data.workspaces.single.label, 'Custom Name');
      expect(data.workspaces.single.path, '/x/y');
    });

    test('hidden ids and hidden types mark snapshot nodes hidden', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'ws:1': [0, 0],
          'repo:1': [10, 0],
        },
        'hidden': ['repo:1'],
        'hiddenTypes': ['workspace'],
      });

      expect(data.workspaces.single.hidden, isTrue);
      expect(data.orphans.single.hidden, isTrue);
      expect(data.hiddenCount, 2);
      expect(data.hiddenTypes, {'workspace'});
    });

    test('snapshot cycle terminates', () {
      final data = buildShowHideSidebarDataFromSnapshotPayload(const {
        'positions': {
          'ws:1': [0, 0],
        },
        'connections': [
          {'from': 'ws:1', 'to': 'ws:1'},
        ],
      });
      expect(data.workspaces.single.children, isEmpty);
    });
  });
}
