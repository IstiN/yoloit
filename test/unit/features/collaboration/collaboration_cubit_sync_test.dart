/// Round-trip tests for [CollaborationCubit]: a real host cubit (with a real
/// [CollaborationServer] on loopback) and real guest cubits exchange
/// [SyncMessage]s over WebSockets, exercising the snapshot builder, the
/// delta broadcast/apply paths, presence handling, terminal streaming and
/// the client-action handlers.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yoloit/features/collaboration/bloc/collaboration_cubit.dart';
import 'package:yoloit/features/collaboration/bloc/collaboration_state.dart';
import 'package:yoloit/features/collaboration/services/guest_terminal_registry.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/review/models/review_models.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/data/terminal_output_bus.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

// ── Shared helpers ───────────────────────────────────────────────────────────

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

/// The host pairs each WS port with `wsPort - 1` for the static HTTP server —
/// return a WS port whose HTTP sibling is also bindable.
Future<int> _freePortPair() async {
  while (true) {
    final wsPort = await _freePort();
    try {
      final probe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        wsPort - 1,
      );
      await probe.close();
      return wsPort;
    } catch (_) {
      // Sibling port busy — try another pair.
    }
  }
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// One of every serialisable node type so `_serializeNodeContent` runs all
/// of its branches while building the snapshot.
List<MindMapNodeData> _hostNodes({String? imagePath}) {
  final t = DateTime(2024);
  return [
    if (imagePath != null)
      // Existing image file: exercises the base64 image branch.
      EditorNodeData(
        id: 'editor:real',
        filePath: imagePath,
        content: '',
        language: '',
      ),
    AgentNodeData(
      id: 'agent:s1',
      session: AgentSession(
        id: 'sess-1',
        type: AgentType.copilot,
        workspacePath: '/proj',
        workspaceId: 'ws-1',
      ),
      workspaceId: 'ws-1',
    ),
    const WorkspaceNodeData(
      id: 'ws:1',
      workspace: Workspace(
        id: 'ws-1',
        name: 'Main',
        paths: ['/a', '/b'],
        color: Color(0xFF123456),
      ),
    ),
    SessionNodeData(
      id: 'sess:1',
      workspaceId: 'ws-1',
      session: AgentSession(
        id: 'sess-2',
        type: AgentType.copilot,
        workspacePath: '/proj',
        status: AgentStatus.live,
      ),
    ),
    const RepoNodeData(
      id: 'repo:1',
      sessionId: 'sess-1',
      repoPath: '/r',
      repoName: 'repo',
      branch: 'main',
    ),
    const BranchNodeData(
      id: 'branch:1',
      repoId: 'repo:1',
      repoName: 'repo',
      branch: 'feat',
      commitHash: 'abc123',
    ),
    const EditorNodeData(
      id: 'editor:1',
      filePath: '/tmp/a.dart',
      content: 'void main() {}',
      language: 'dart',
    ),
    // Image path that does not exist: exercises the image-detection branch
    // and the read-failure fall-through to text serialisation.
    const EditorNodeData(
      id: 'editor:img',
      filePath: '/definitely/missing/pic.png',
      content: '',
      language: '',
    ),
    const FilePanelNodeData(id: 'panel:1', filePath: '/tmp/x.md'),
    const FileDiffPanelNodeData(
      id: 'filediff:1',
      filePath: '/tmp/x.md',
      repoPath: '/r',
    ),
    const FilesNodeData(
      id: 'files:1',
      sessionId: 'sess-1',
      repoPath: '/r',
      changedFiles: [
        FileChange(
          path: 'a.dart',
          status: FileChangeStatus.modified,
          addedLines: 3,
          removedLines: 1,
        ),
      ],
    ),
    const FileTreeNodeData(
      id: 'tree:1',
      workspaceId: 'ws-1',
      repoPath: '/r',
      repoName: 'repo',
    ),
    const DiffNodeData(
      id: 'diff:1',
      workspaceId: 'ws-1',
      repoPath: '/r',
      repoName: 'repo',
    ),
    RunNodeData(
      id: 'run:1',
      workspaceId: 'ws-1',
      session: RunSession(
        id: 'run-1',
        config: const RunConfig(id: 'rc', name: 'Build', command: 'make'),
        workspacePath: '/proj',
        status: RunStatus.running,
        output: [
          RunOutputLine(text: 'hello', isError: false, timestamp: t),
          RunOutputLine(text: 'oops', isError: true, timestamp: t),
        ],
      ),
    ),
    const MindMapPluginNodeData(
      id: 'plugin:1',
      pluginId: 'com.example.p',
      columnIndex: 0,
      typeTag: 'plugin',
      defaultSize: Size(100, 100),
      payload: {'k': 'v'},
    ),
  ];
}

/// Duck-typed stand-ins for ReviewState diff models: the props builder reads
/// `hunk.header`, `hunk.lines`, `line.content` and `line.type.name` via
/// dynamic access, so plain Maps do not work here.
class _FakeDiffHunk {
  const _FakeDiffHunk({required this.header, required this.lines});
  final String header;
  final List<_FakeDiffLine> lines;
}

class _FakeDiffLine {
  const _FakeDiffLine({required this.content, required this.type});
  final String content;
  final _FakeDiffLineType type;
}

class _FakeDiffLineType {
  const _FakeDiffLineType(this.name);
  final String name;
}

/// Minimal stand-in for ReviewCubit: exposes a Map-shaped `state` the card
/// props builders can read (`fileTree`, `changedFiles`, `diffHunks`).
class _FakeReviewCubit {
  final state = <String, dynamic>{
    'fileTree': [
      {
        'name': 'r',
        'path': '/r',
        'isDir': true,
        'isExpanded': true,
        'children': [
          {
            'name': 'a.dart',
            'path': '/r/a.dart',
            'isDir': false,
            'isExpanded': false,
          },
        ],
      },
    ],
    'changedFiles': [
      {
        'path': 'a.dart',
        'status': 'modified',
        'addedLines': 1,
        'removedLines': 2,
        'repoPath': '/r',
      },
    ],
    'selectedFilePath': '/r/a.dart',
    'diffHunks': [
      const _FakeDiffHunk(
        header: '@@ -1 +1 @@',
        lines: [
          _FakeDiffLine(
            content: '+x',
            type: _FakeDiffLineType('add'),
          ),
          _FakeDiffLine(
            content: '-y',
            type: _FakeDiffLineType('remove'),
          ),
        ],
      ),
    ],
  };
}

/// A running host + connected guest pair on real loopback sockets.
class _Pair {
  late final MindMapCubit hostMap;
  late final CollaborationCubit host;
  late final MindMapCubit guestMap;
  late final CollaborationCubit guest;
  final terminalInputs = <(String, String)>[];
  final actionLog = <String>[];
  Directory? _tmpDir;

  Future<void> start({
    bool seedNodes = true,
    Completer<void>? editorSaveGate,
    String? prefillOutput,
  }) async {
    String? imagePath;
    if (seedNodes) {
      _tmpDir = Directory.systemTemp.createTempSync('collab_cubit_test');
      imagePath = '${_tmpDir!.path}/pic.png';
      File(imagePath).writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    }
    hostMap = MindMapCubit();
    host = CollaborationCubit(
      mindMapCubit: hostMap,
      reviewCubit: _FakeReviewCubit(),
      listDirectory: (repoPath) => [
        {'name': 'f.txt', 'path': '$repoPath/f.txt', 'isDir': false},
      ],
      onTerminalInput: (id, data) => terminalInputs.add((id, data)),
      onCreateWorkspace: (payload) =>
          actionLog.add('workspace_create:${payload['name']}'),
      onAddFolder: (nodeId, {path}) =>
          actionLog.add('ws_add_folder:$nodeId:$path'),
      // Async on purpose: exercises the future branch of `_runAction`.
      onCreateSession: (nodeId) async =>
          actionLog.add('ws_create_session:$nodeId'),
      onRunStart: (nodeId) => actionLog.add('run_start:$nodeId'),
      onRunStop: (nodeId) => actionLog.add('run_stop:$nodeId'),
      onRunRestart: (nodeId) => actionLog.add('run_restart:$nodeId'),
      onFileSelect: (nodeId, path) => actionLog.add('file_select:$nodeId:$path'),
      onTreeToggle: (nodeId, path) =>
          actionLog.add('tree_toggle:$nodeId:$path'),
      onTreeSelect: (nodeId, path) =>
          actionLog.add('tree_select:$nodeId:$path'),
      onEditorSwitchTab: (nodeId, tabIndex) =>
          actionLog.add('editor_switch_tab:$nodeId:$tabIndex'),
      onEditorSave: (nodeId) async {
        actionLog.add('editor_save:$nodeId');
        await editorSaveGate?.future;
      },
      onEditorContentUpdate: (nodeId, content) =>
          actionLog.add('editor_content_update:$nodeId:$content'),
      onSessionStart: (nodeId) => actionLog.add('session_start:$nodeId'),
    );
    if (seedNodes) {
      final nodes = _hostNodes(imagePath: imagePath);
      if (prefillOutput != null) {
        // Give the agent session raw history so the host replays it to the
        // guest right after the hello handshake.
        nodes.whereType<AgentNodeData>().first.session
            .appendOutput(prefillOutput);
      }
      hostMap.applyRemoteSnapshot(
        positions: {for (final n in nodes) n.id: const Offset(1, 2)},
        sizes: {for (final n in nodes) n.id: const Size(200, 100)},
        hidden: {'files:1'},
        hiddenTypes: {'files'},
        connections: const [
          MindMapConnection(
            fromId: 'ws:1',
            toId: 'agent:s1',
            style: ConnectorStyle.dashed,
            color: Color(0xFF00FF00),
          ),
        ],
        savedViews: const {},
        remoteNodes: nodes,
      );
    }
    await host.startHosting(port: await _freePortPair());
    expect(host.state.mode, CollaborationMode.hosting);

    guestMap = MindMapCubit();
    guest = CollaborationCubit(mindMapCubit: guestMap);
    final wsPort = int.parse(host.state.address.split(':').last);
    await guest.connect('127.0.0.1', port: wsPort);
    expect(guest.state.mode, CollaborationMode.connected);
    await _waitFor(() => host.state.peers.isNotEmpty);
    if (seedNodes) {
      await _waitFor(() => guestMap.state.nodes.isNotEmpty);
    }
  }

  Future<void> dispose() async {
    await guest.close();
    await host.close();
    await guestMap.close();
    await hostMap.close();
    final dir = _tmpDir;
    if (dir != null) {
      _tmpDir = null;
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Secure storage is empty: no E2EE key, fresh client id per connect.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async => null);
    GuestTerminalRegistry.instance.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
    GuestTerminalRegistry.instance.clear();
  });

  group('snapshot (host → guest)', () {
    late _Pair pair;

    setUp(() async {
      pair = _Pair();
      await pair.start();
    });

    tearDown(() => pair.dispose());

    test('guest applies the full snapshot on connect', () {
      final state = pair.guestMap.state;
      // Geometry and visibility.
      expect(state.positions['repo:1'], const Offset(1, 2));
      expect(state.sizes['repo:1'], const Size(200, 100));
      expect(state.hidden, contains('files:1'));
      expect(state.hiddenTypes, contains('files'));
      // Connections round-trip with style and colour.
      expect(state.connections, hasLength(1));
      expect(state.connections.single.fromId, 'ws:1');
      expect(state.connections.single.toId, 'agent:s1');
      expect(state.connections.single.style, ConnectorStyle.dashed);
      expect(state.connections.single.color, const Color(0xFF00FF00));
      // Custom workspace colours are synced.
      expect(state.nodeColors['ws:1'], 0xFF123456);
      // Every node type was serialised into nodeContent.
      final nc = state.nodeContent;
      expect(nc['agent:s1']!['type'], 'agent');
      expect(nc['ws:1']!['type'], 'workspace');
      expect(nc['sess:1']!['type'], 'session');
      expect(nc['sess:1']!['isRunning'], isTrue);
      expect(nc['repo:1']!['type'], 'repo');
      expect(nc['branch:1']!['type'], 'branch');
      expect(nc['editor:1']!['type'], 'editor');
      expect(nc['editor:1']!['content'], 'void main() {}');
      // Existing image file is sent as base64 bytes.
      expect(nc['editor:real']!['type'], 'editor');
      expect(nc['editor:real']!['imageBase64'], isNotEmpty);
      // Missing image file falls back to text serialisation.
      expect(nc['editor:img']!['type'], 'editor');
      expect(nc['editor:img']!.containsKey('imageBase64'), isFalse);
      expect(nc['panel:1']!['type'], 'panel');
      expect(nc['filediff:1']!['type'], 'filediff');
      expect(nc['files:1']!['type'], 'files');
      expect(nc['tree:1']!['type'], 'tree');
      expect((nc['tree:1']!['entries'] as List), hasLength(2));
      expect(nc['diff:1']!['type'], 'diff');
      final hunks = nc['diff:1']!['hunks'] as List;
      expect(hunks, hasLength(1));
      expect((hunks.single as Map<String, dynamic>)['header'], '@@ -1 +1 @@');
      expect(
        ((hunks.single as Map<String, dynamic>)['lines'] as List),
        hasLength(2),
      );
      expect(nc['run:1']!['type'], 'run');
      expect(nc['run:1']!['isRunning'], isTrue);
      expect((nc['run:1']!['lines'] as List), hasLength(2));
      expect(nc['plugin:1']!['type'], 'plugin');
      expect(nc['plugin:1']!['payload'], {'k': 'v'});
      // Deserializable remote nodes are materialised on the guest.
      final panel = state.nodes.singleWhere((n) => n.id == 'panel:1');
      expect(panel, isA<FilePanelNodeData>());
      expect((panel as FilePanelNodeData).filePath, '/tmp/x.md');
      // Presence: the host registered the guest hello, the guest got the
      // server connected/presence broadcasts.
      expect(pair.host.state.peers, isNotEmpty);
      expect(pair.guest.state.peerCount, greaterThanOrEqualTo(1));
    });

    test('position, size and visibility deltas propagate to the guest',
        () async {
      pair.hostMap.applyRemoteMove('repo:1', const Offset(10, 20));
      await _waitFor(
        () => pair.guestMap.state.positions['repo:1'] == const Offset(10, 20),
      );
      // The first state change after the guest connects goes out as a full
      // snapshot; a second move exercises the position-delta broadcast and
      // the guest-side delta.move handler.
      pair.hostMap.applyRemoteMove('repo:1', const Offset(11, 21));
      await _waitFor(
        () => pair.guestMap.state.positions['repo:1'] == const Offset(11, 21),
      );

      pair.hostMap.applyRemoteResize('repo:1', const Size(300, 200));
      await _waitFor(
        () => pair.guestMap.state.sizes['repo:1'] == const Size(300, 200),
      );

      pair.hostMap.hideNode('repo:1');
      await _waitFor(() => pair.guestMap.state.hidden.contains('repo:1'));
      pair.hostMap.showNode('repo:1');
      await _waitFor(() => !pair.guestMap.state.hidden.contains('repo:1'));
    });

    test('a structural change rebroadcasts a full snapshot', () async {
      pair.hostMap.applyRemoteSnapshot(
        positions: const {},
        sizes: const {},
        hidden: const {},
        hiddenTypes: const {},
        remoteNodes: const [
          FilePanelNodeData(id: 'panel:2', filePath: '/tmp/y.md'),
        ],
      );
      await _waitFor(
        () => pair.guestMap.state.nodes.any((n) => n.id == 'panel:2'),
      );
      // The previously synced node is preserved.
      expect(pair.guestMap.state.nodes.any((n) => n.id == 'panel:1'), isTrue);
    });

    test('host broadcasts a fresh snapshot on demand', () async {
      pair.hostMap.applyRemoteMove('repo:1', const Offset(7, 7));
      // No delta listener timing assumptions — broadcastSnapshot pushes the
      // current state directly.
      pair.host.broadcastSnapshot();
      await _waitFor(
        () => pair.guestMap.state.positions['repo:1'] == const Offset(7, 7),
      );
    });
  });

  group('deltas (guest → host)', () {
    late _Pair pair;

    setUp(() async {
      pair = _Pair();
      await pair.start();
    });

    tearDown(() => pair.dispose());

    test('guest move and resize are applied on the host', () async {
      pair.guest.sendGuestMove('repo:1', const Offset(5, 6));
      await _waitFor(
        () => pair.hostMap.state.positions['repo:1'] == const Offset(5, 6),
      );

      pair.guest.sendGuestResize('repo:1', const Size(111, 222));
      await _waitFor(
        () => pair.hostMap.state.sizes['repo:1'] == const Size(111, 222),
      );
    });

    test('guest toggle deltas hide and show nodes on the host', () async {
      pair.guest
          .sendGuestEvent('delta.toggle', {'id': 'repo:1', 'hidden': true});
      await _waitFor(() => pair.hostMap.state.hidden.contains('repo:1'));

      pair.guest
          .sendGuestEvent('delta.toggle', {'id': 'repo:1', 'hidden': false});
      await _waitFor(() => !pair.hostMap.state.hidden.contains('repo:1'));
    });

    test('unknown message types from the guest are ignored', () async {
      pair.guest.sendGuestEvent('bogus.type', {'id': 'repo:1'});
      pair.guest.sendGuestMove('repo:1', const Offset(9, 9));
      await _waitFor(
        () => pair.hostMap.state.positions['repo:1'] == const Offset(9, 9),
      );
      expect(pair.actionLog, isEmpty);
    });
  });

  group('terminal streaming', () {
    late _Pair pair;

    setUp(() async {
      pair = _Pair();
      await pair.start();
    });

    tearDown(() => pair.dispose());

    test('guest keyboard input reaches the host PTY callback', () async {
      // Agent node id resolves to the underlying PTY session id.
      pair.guest.sendTerminalInput('agent:s1', 'ls\n');
      await _waitFor(
        () => pair.terminalInputs.contains(('sess-1', 'ls\n')),
      );
      // Unknown ids pass through unchanged.
      pair.guest.sendTerminalInput('raw-id', 'x');
      await _waitFor(() => pair.terminalInputs.contains(('raw-id', 'x')));
      // Empty payloads are dropped.
      pair.guest.sendTerminalInput('agent:s1', '');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pair.terminalInputs, hasLength(2));
    });

    test('host terminal output lands in the guest terminal registry',
        () async {
      // Unknown sessions are dropped without a broadcast.
      TerminalOutputBus.instance.write('no-such-session', 'ignored');
      TerminalOutputBus.instance.write('sess-1', 'raw-out');
      await _waitFor(() {
        final terminal =
            GuestTerminalRegistry.instance.terminalFor('agent:s1');
        return [
          for (var i = 0; i < terminal.lines.length; i++) terminal.lines[i],
        ].any((line) => line.toString().contains('raw-out'));
      });
    });

    test('host replays terminal history to a freshly connected guest',
        () async {
      final replay = _Pair();
      await replay.start(prefillOutput: 'history-bytes');
      try {
        await _waitFor(() {
          final terminal =
              GuestTerminalRegistry.instance.terminalFor('agent:s1');
          return [
            for (var i = 0; i < terminal.lines.length; i++) terminal.lines[i],
          ].any((line) => line.toString().contains('history-bytes'));
        });
      } finally {
        await replay.dispose();
      }
    });
  });

  group('presence', () {
    late _Pair pair;

    setUp(() async {
      pair = _Pair();
      await pair.start();
    });

    tearDown(() => pair.dispose());

    test('second guest join and leave update the first guest peers', () async {
      final guest2Map = MindMapCubit();
      final guest2 = CollaborationCubit(mindMapCubit: guest2Map);
      final wsPort = int.parse(pair.host.state.address.split(':').last);
      await guest2.connect('127.0.0.1', port: wsPort);
      await _waitFor(() => pair.guest.state.peerCount == 2);

      // Cursor moves are relayed peer-to-peer; the handler is a no-op for
      // now and must not disturb presence state.
      guest2.sendGuestEvent('cursor.move', {
        'id': 'g2',
        'x': 1.0,
        'y': 2.0,
        'color': '#FFF',
        'name': 'G2',
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pair.guest.state.peerCount, 2);

      await guest2.disconnect();
      await _waitFor(() => pair.guest.state.peerCount == 1);
      await guest2.close();
      await guest2Map.close();
    });

    test('stopping the host disconnects the guest', () async {
      await pair.host.stopHosting();
      expect(pair.host.state.isIdle, isTrue);
      await _waitFor(() => pair.guest.state.isIdle);
    });
  });

  group('client action handlers', () {
    late _Pair pair;

    setUp(() async {
      pair = _Pair();
      await pair.start();
    });

    tearDown(() => pair.dispose());

    test('every action message invokes its host callback', () async {
      pair.guest.sendGuestEvent('workspace_create', {'name': 'W'});
      pair.guest.sendGuestEvent('ws_add_folder', {'id': 'n1', 'path': '/p'});
      pair.guest.sendGuestEvent('ws_create_session', {'id': 'n1'});
      pair.guest.sendGuestEvent('run_start', {'id': 'n1'});
      pair.guest.sendGuestEvent('run_stop', {'id': 'n1'});
      pair.guest.sendGuestEvent('run_restart', {'id': 'n1'});
      pair.guest.sendGuestEvent('file_select', {'id': 'n1', 'path': '/f'});
      pair.guest.sendGuestEvent('tree_toggle', {'id': 'n1', 'path': '/t'});
      pair.guest.sendGuestEvent('tree_select', {'id': 'n1', 'path': '/s'});
      pair.guest
          .sendGuestEvent('editor_switch_tab', {'id': 'n1', 'tabIndex': 2});
      pair.guest.sendGuestEvent('editor_save', {'id': 'n1'});
      pair.guest
          .sendGuestEvent('editor_content_update', {'id': 'n1', 'content': 'c'});
      pair.guest.sendGuestEvent('session_start', {'id': 'n1'});

      await _waitFor(() => pair.actionLog.length == 13);
      expect(
        pair.actionLog,
        containsAll([
          'workspace_create:W',
          'ws_add_folder:n1:/p',
          'ws_create_session:n1',
          'run_start:n1',
          'run_stop:n1',
          'run_restart:n1',
          'file_select:n1:/f',
          'tree_toggle:n1:/t',
          'tree_select:n1:/s',
          'editor_switch_tab:n1:2',
          'editor_save:n1',
          'editor_content_update:n1:c',
          'session_start:n1',
        ]),
      );
      // Synchronous remote actions reset the auto-pan guard.
      expect(pair.host.isHandlingRemoteAction, isFalse);
    });

    test('invalid action payloads are dropped without invoking callbacks',
        () async {
      pair.guest.sendGuestEvent('run_start', {'id': ''});
      pair.guest.sendGuestEvent('file_select', {'id': 'n1', 'path': ''});
      pair.guest.sendGuestEvent('editor_switch_tab', {'id': 'n1'});
      // Follow with a valid message so we know the invalid ones were processed.
      pair.guest.sendGuestEvent('run_stop', {'id': 'n1'});
      await _waitFor(() => pair.actionLog.contains('run_stop:n1'));
      expect(pair.actionLog, hasLength(1));
    });

    test('remote-action guard stays set while an async callback runs',
        () async {
      final gate = Completer<void>();
      final gated = _Pair();
      await gated.start(seedNodes: false, editorSaveGate: gate);
      try {
        gated.guest.sendGuestEvent('editor_save', {'id': 'n1'});
        await _waitFor(() => gated.actionLog.contains('editor_save:n1'));
        // The callback future is still pending — the guard must be set.
        expect(gated.host.isHandlingRemoteAction, isTrue);
        gate.complete();
        await _waitFor(() => !gated.host.isHandlingRemoteAction);
      } finally {
        await gated.dispose();
      }
    });
  });

  group('lifecycle and error paths', () {
    test('send helpers are no-ops while not connected', () async {
      final map = MindMapCubit();
      final cubit = CollaborationCubit(mindMapCubit: map);
      cubit.sendGuestMove('n1', const Offset(1, 1));
      cubit.sendGuestResize('n1', const Size(1, 1));
      cubit.sendGuestEvent('run_start', {'id': 'n1'});
      cubit.sendTerminalInput('n1', 'x');
      cubit.broadcastSnapshot();
      expect(cubit.state.isIdle, isTrue);
      await cubit.close();
      await map.close();
    });

    test('connect to a closed port surfaces an error', () async {
      final map = MindMapCubit();
      final cubit = CollaborationCubit(mindMapCubit: map);
      await cubit.connect('127.0.0.1', port: await _freePort());
      expect(cubit.state.mode, CollaborationMode.idle);
      expect(cubit.state.error, contains('Connection failed'));
      await cubit.close();
      await map.close();
    });

    test('startHosting exhausts retries and reports the failure', () async {
      // Occupy the preferred port and every fallback offset (+2 … +8).
      final preferred = await _freePortPair();
      final blockers = <ServerSocket>[];
      for (var offset = 0; offset <= 8; offset += 2) {
        blockers.add(
          await ServerSocket.bind(InternetAddress.anyIPv4, preferred + offset),
        );
      }
      final map = MindMapCubit();
      final cubit = CollaborationCubit(mindMapCubit: map);
      try {
        await cubit.startHosting(port: preferred);
        expect(cubit.state.mode, CollaborationMode.idle);
        expect(cubit.state.startingHost, isFalse);
        expect(cubit.state.error, contains('Failed to start server'));
      } finally {
        await cubit.close();
        await map.close();
        for (final socket in blockers) {
          await socket.close();
        }
      }
    });
  });
}
