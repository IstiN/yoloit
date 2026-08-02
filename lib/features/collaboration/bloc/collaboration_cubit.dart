import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/collaboration/bloc/collaboration_state.dart';
import 'package:yoloit/features/collaboration/collaboration_ports.dart';
import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/collaboration/services/collaboration_cipher.dart';
import 'package:yoloit/features/collaboration/services/collaboration_client.dart';
import 'package:yoloit/features/collaboration/services/collaboration_key_store.dart';
import 'package:yoloit/features/collaboration/services/collaboration_server_platform.dart';
import 'package:yoloit/features/collaboration/services/guest_terminal_registry.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/agent_card_props_builder.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/editor_card_props_builder.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/review_card_props_builder.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/data/terminal_output_bus.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';

/// Resolves a collaboration terminal target to the underlying PTY session id.
String resolveTerminalSessionId(
  String nodeId,
  Iterable<MindMapNodeData> nodes,
) {
  for (final node in nodes.whereType<AgentNodeData>()) {
    if (node.id == nodeId) return node.session.id;
  }
  const prefix = 'agent:';
  return nodeId.startsWith(prefix) ? nodeId.substring(prefix.length) : nodeId;
}

/// Orchestrates real-time collaboration over a local WebSocket connection.
///
/// **Host mode**: starts [CollaborationServer], subscribes to the legacy
/// [MindMapCubit] collaboration backend, and broadcasts JSON snapshots/deltas
/// to all connected clients. TODO(board-collab): move this transport to
/// BoardCubit once Board View supports browser guests.
///
/// **Guest mode**: starts [CollaborationClient], receives JSON messages, and
/// applies them to the local [MindMapCubit].
class CollaborationCubit extends Cubit<CollaborationState> {
  /// [onTerminalInput] receives (sessionId, data) when a browser guest sends
  /// keyboard input to a terminal.  Pass [PtyService.instance.write] on the
  /// host (macOS); leave null on web guests where PtyService is unavailable.
  ///
  /// [ensureNodesPopulated] is called before sending the first snapshot when
  /// the legacy collaboration backend has no positions. The host (macOS
  /// app.dart) provides a callback that reads workspace and terminal state and
  /// calls [mindMapCubit.updateNodes]; leave null on web.
  CollaborationCubit({
    required this.mindMapCubit,
    this.ensureNodesPopulated,
    this.onTerminalInput,
    this.reviewCubit,
    this.fileEditorCubit,
    this.listDirectory,
    this.onCreateWorkspace,
    this.onAddFolder,
    this.onCreateSession,
    this.onRunStart,
    this.onRunStop,
    this.onRunRestart,
    this.onFileSelect,
    this.onTreeToggle,
    this.onTreeSelect,
    this.onEditorSwitchTab,
    this.onEditorSave,
    this.onEditorContentUpdate,
    this.onSessionStart,
  }) : super(const CollaborationState());

  final MindMapCubit mindMapCubit;
  final Future<void> Function()? ensureNodesPopulated;
  final void Function(String sessionId, String data)? onTerminalInput;
  final dynamic reviewCubit; // ReviewCubit on desktop, null on web
  final dynamic fileEditorCubit; // FileEditorCubit on desktop, null on web
  /// Lists top-level directory entries for a repo path (host only).
  /// Returns list of {name, path, isDir} maps, or null if unavailable.
  final List<Map<String, dynamic>> Function(String repoPath)? listDirectory;
  final FutureOr<void> Function(Map<String, dynamic> payload)? onCreateWorkspace;
  final FutureOr<void> Function(String nodeId, {String? path})? onAddFolder;
  final FutureOr<void> Function(String nodeId)? onCreateSession;
  final FutureOr<void> Function(String nodeId)? onRunStart;
  final FutureOr<void> Function(String nodeId)? onRunStop;
  final FutureOr<void> Function(String nodeId)? onRunRestart;
  final FutureOr<void> Function(String nodeId, String path)? onFileSelect;
  final FutureOr<void> Function(String nodeId, String path)? onTreeToggle;
  final FutureOr<void> Function(String nodeId, String path)? onTreeSelect;
  final FutureOr<void> Function(String nodeId, int tabIndex)? onEditorSwitchTab;
  final FutureOr<void> Function(String nodeId)? onEditorSave;
  final FutureOr<void> Function(String nodeId, String content)? onEditorContentUpdate;
  final FutureOr<void> Function(String nodeId)? onSessionStart;

  CollaborationServer? _server;
  CollaborationClient? _client;
  CollaborationCipher? _cipher;
  StreamSubscription<MindMapState>? _stateSub;
  StreamSubscription<(String, String)>? _terminalSub;
  MindMapState? _lastBroadcast;

  /// True while a remote-client action (tree_select, file_select, etc.)
  /// is being handled. The host mindmap view should NOT auto-pan in this case.
  bool _handlingRemoteAction = false;
  bool get isHandlingRemoteAction => _handlingRemoteAction;

  // ── Host ─────────────────────────────────────────────────────────────────

  Future<void> startHosting({int port = kDefaultWsPort}) async {
    if (!state.isIdle) return;
    if (_server != null) {
      await stopHosting();
    }
    emit(
      state.copyWith(
        error: '',
        address: '',
        webClientUrl: '',
        localUrl: '',
        peerCount: 0,
        peers: const {},
        startingHost: true,
      ),
    );

    // Load E2EE cipher once — non-null if a key exists in secure storage.
    _cipher = await CollaborationKeyStore.loadCipher();

    Object? lastError;
    for (final attempt in _hostingAttempts(port)) {
      if (attempt.delay > Duration.zero) {
        await Future<void>.delayed(attempt.delay);
      }
      try {
        _server = CollaborationServer(
          port: attempt.wsPort,
          httpPort: attempt.httpPort,
          onClientMessage: _onClientMessage,
          cipher: _cipher,
        );
        final address = await _server!.start();
        _finishHosting(address);
        return;
      } catch (e) {
        lastError = e;
        await _server?.stop();
        _server = null;
        if (!_isAddressInUseError(e)) {
          break;
        }
      }
    }
    emit(
      state.copyWith(
        error: 'Failed to start server: ${lastError ?? 'unknown error'}',
        startingHost: false,
      ),
    );
  }

  void _finishHosting(String address) {
    _stateSub = mindMapCubit.stream.listen(_onMindMapStateChanged);
    _terminalSub = TerminalOutputBus.instance.stream.listen(_onTerminalData);
    emit(
      state.copyWith(
        mode: CollaborationMode.hosting,
        address: address,
        webClientUrl: _server!.webClientUrl,
        localUrl: _server!.localUrl,
        error: '',
        startingHost: false,
        encryptionEnabled: _cipher != null,
      ),
    );
  }

  Iterable<({int wsPort, int httpPort, Duration delay})> _hostingAttempts(
    int preferredWsPort,
  ) sync* {
    final preferredHttpPort = preferredWsPort - 1;
    yield (
      wsPort: preferredWsPort,
      httpPort: preferredHttpPort,
      delay: Duration.zero,
    );
    yield (
      wsPort: preferredWsPort,
      httpPort: preferredHttpPort,
      delay: const Duration(milliseconds: 400),
    );
    yield (
      wsPort: preferredWsPort,
      httpPort: preferredHttpPort,
      delay: const Duration(milliseconds: 1200),
    );
    for (var offset = 2; offset <= 8; offset += 2) {
      yield (
        wsPort: preferredWsPort + offset,
        httpPort: preferredHttpPort + offset,
        delay: Duration.zero,
      );
    }
  }

  bool _isAddressInUseError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('address already in use') ||
        text.contains('shared flag to bind() needs to be `true`') ||
        text.contains('same (address, port) combination') ||
        text.contains('errno = 48') ||
        text.contains('errno 48');
  }

  Future<void> stopHosting() async {
    await _server?.stop();
    await _stateSub?.cancel();
    await _terminalSub?.cancel();
    _server = null;
    _stateSub = null;
    _terminalSub = null;
    _lastBroadcast = null;
    emit(const CollaborationState());
  }

  // ── Guest ────────────────────────────────────────────────────────────────

  Future<void> connect(String host, {int port = kDefaultWsPort}) async {
    if (!state.isIdle) return;
    emit(state.copyWith(error: ''));
    try {
      _cipher = await CollaborationKeyStore.loadCipher();
      final clientId = await CollaborationKeyStore.getOrCreateClientId();
      _client = CollaborationClient(
        onMessage: _onMessageFromHost,
        cipher: _cipher,
      );
      await _client!.connect(
        host,
        port,
        clientId: clientId,
        clientName: 'Remote Guest',
      );
      emit(
        state.copyWith(
          mode: CollaborationMode.connected,
          address: '$host:$port',
          encryptionEnabled: _cipher != null,
        ),
      );
    } catch (e) {
      _client = null;
      emit(state.copyWith(error: 'Connection failed: $e'));
    }
  }

  /// Guest: send a node move to the host (used from web/remote canvas).
  void sendGuestMove(String nodeId, Offset pos) {
    _client?.sendMessage(
      SyncMessage.move(nodeId, pos.dx, pos.dy, senderId: 'guest'),
    );
  }

  /// Guest: send a node resize to the host.
  void sendGuestResize(String nodeId, Size size) {
    _client?.sendMessage(
      SyncMessage.resize(nodeId, size.width, size.height, senderId: 'guest'),
    );
  }

  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
    emit(const CollaborationState());
  }

  // ── Host: MindMap → broadcast ─────────────────────────────────────────────

  void _onMindMapStateChanged(MindMapState mmState) {
    final prev = _lastBroadcast;
    _lastBroadcast = mmState;
    if (_server == null || _server!.clientCount == 0) return;

    if (prev == null) {
      _server!.broadcastRaw(_buildSnapshot(mmState));
      return;
    }

    // When structural / non-delta-able fields change (hiddenTypes, connections,
    // savedViews, nodes), broadcast a full snapshot rather than fine-grained
    // deltas that cannot express these changes.
    if (!identical(mmState.hiddenTypes, prev.hiddenTypes) ||
        !identical(mmState.connections, prev.connections) ||
        !identical(mmState.savedViews, prev.savedViews) ||
        !identical(mmState.nodes, prev.nodes)) {
      _server!.broadcastRaw(_buildSnapshot(mmState));
      return;
    }

    for (final entry in mmState.positions.entries) {
      final old = prev.positions[entry.key];
      if (old == null || old != entry.value) {
        _server!.broadcastRaw(
          SyncMessage.move(entry.key, entry.value.dx, entry.value.dy),
        );
      }
    }
    for (final entry in mmState.sizes.entries) {
      final old = prev.sizes[entry.key];
      if (old == null || old != entry.value) {
        _server!.broadcastRaw(
          SyncMessage.resize(entry.key, entry.value.width, entry.value.height),
        );
      }
    }
    for (final id in mmState.hidden.difference(prev.hidden)) {
      _server!.broadcastRaw(SyncMessage.toggle(id, hidden: true));
    }
    for (final id in prev.hidden.difference(mmState.hidden)) {
      _server!.broadcastRaw(SyncMessage.toggle(id, hidden: false));
    }
  }

  SyncMessage _buildSnapshot(MindMapState mm) {
    final ncEntries = mm.nodes.map((n) {
      return MapEntry(n.id, _serializeNodeContent(n));
    }).toList();
    final savedViewsMap = mm.savedViews.map(
      (k, v) => MapEntry(k, v.toJson().cast<String, dynamic>()),
    );
    // Extract custom colours for workspace cards so guests can display them.
    final nodeColorsMap = <String, int>{};
    for (final node in mm.nodes) {
      if (node is WorkspaceNodeData && node.workspace.color != null) {
        nodeColorsMap[node.id] = node.workspace.color!.toARGB32();
      }
    }
    return SyncMessage.snapshot(
      positions: mm.positions.map((k, v) => MapEntry(k, [v.dx, v.dy])),
      sizes: mm.sizes.map((k, v) => MapEntry(k, [v.width, v.height])),
      hidden: mm.hidden.toList(),
      hiddenTypes: mm.hiddenTypes.toList(),
      connections: mm.connections
          .map(
            (c) => {
              'from': c.fromId,
              'to': c.toId,
              'style': c.style.name,
              'color': c.color.toARGB32(),
            },
          )
          .toList(),
      nodeContent: Map.fromEntries(ncEntries),
      savedViews: savedViewsMap,
      nodeColors: nodeColorsMap,
    );
  }

  Map<String, dynamic> _serializeNodeContent(MindMapNodeData node) {
    return switch (node) {
      final AgentNodeData d => _serializeAgent(d),
      final WorkspaceNodeData d => {
        'type': 'workspace',
        'name': d.workspace.name,
        'path': d.workspace.path,
        'paths': d.workspace.paths,
        'color': d.workspace.color?.value,
      },
      final SessionNodeData d => {
        'type': 'session',
        'name': d.session.customName ?? d.session.id,
        'typeName': d.session.type.name,
        'status': d.session.status.name,
        'isRunning': d.session.status == AgentStatus.live,
        'isLive': d.session.status == AgentStatus.live,
        'workspaceId': d.workspaceId,
        'lastLines': d.session.lastLines(80),
      },
      final RepoNodeData d => {
        'type': 'repo',
        'name': d.repoName,
        'path': d.repoPath,
        'branch': d.branch,
      },
      final BranchNodeData d => {
        'type': 'branch',
        'name': d.branch,
        'repoName': d.repoName,
        'commitHash': d.commitHash,
      },
      final EditorNodeData d => _serializeEditor(d),
      final FilePanelNodeData d => {
        'type': 'panel',
        'filePath': d.filePath,
      },
      final FileDiffPanelNodeData d => {
        'type': 'filediff',
        'filePath': d.filePath,
        'repoPath': d.repoPath,
      },
      final FilesNodeData d => {
        'type': 'files',
        'repoPath': d.repoPath,
        'files': d.changedFiles
            .map(
              (f) => {
                'path': f.path,
                'status': f.status.name,
                'addedLines': f.addedLines,
                'removedLines': f.removedLines,
              },
            )
            .toList(),
      },
      final FileTreeNodeData d => {
        'type': 'tree',
        'workspaceId': d.workspaceId,
        'repoPath': d.repoPath,
        'repoName': d.repoName,
        'entries': _serializeFileTree(d.repoPath ?? '', repoName: d.repoName),
      },
      final DiffNodeData d => {
        'type': 'diff',
        'workspaceId': d.workspaceId,
        'repoPath': d.repoPath,
        'repoName': d.repoName,
        'hunks': _serializeDiffHunks(d.repoPath ?? '', repoName: d.repoName),
      },
      final RunNodeData d => {
        'type': 'run',
        'name': d.session.config.name,
        'status': d.session.status.name,
        'isRunning': d.session.status == RunStatus.running,
        'lines': d.session.output.reversed
            .take(80)
            .toList()
            .reversed
            .map((l) => {'text': l.text, 'isError': l.isError})
            .toList(),
        'lastLines': d.session.output.reversed
            .take(80)
            .toList()
            .reversed
            .map((l) => l.text)
            .toList(),
      },
      final MindMapPluginNodeData d => {
        'type': 'plugin',
        'pluginId': d.pluginId,
        'payload': d.payload,
      },
    };
  }

  /// Flattens the ReviewCubit file tree for [repoPath] into serializable entries.
  /// Falls back to [listDirectory] if ReviewCubit doesn't have the requested repo.
  List<Map<String, dynamic>> _serializeFileTree(
    String repoPath, {
    String? repoName,
  }) {
    final props = buildFileTreeCardProps(
      repoPath: repoPath,
      repoName: repoName,
      reviewState: reviewCubit?.state,
      listDirectory: listDirectory,
    );
    return props.entries
        .map(
          (entry) => {
            'name': entry.name,
            'path': entry.path,
            'isDir': entry.isDir,
            'depth': entry.depth,
            'isExpanded': entry.isExpanded,
          },
        )
        .toList();
  }

  /// Serializes diff hunks from ReviewCubit state for [repoPath].
  List<Map<String, dynamic>> _serializeDiffHunks(
    String repoPath, {
    String? repoName,
  }) {
    final props = buildDiffCardProps(
      repoPath: repoPath,
      repoName: repoName,
      reviewState: reviewCubit?.state,
    );
    return props.hunks
        .map(
          (hunk) => {
            'header': hunk.header,
            'lines': hunk.lines
                .map((line) => {'text': line.text, 'type': line.type})
                .toList(),
          },
        )
        .toList();
  }

  Map<String, dynamic> _serializeAgent(AgentNodeData data) {
    final props = buildAgentCardProps(data);
    return {
      'type': 'agent',
      'name': props.name,
      'status': props.status,
      'isRunning': props.isRunning,
      'isIdle': props.isIdle,
      'typeName': props.typeName,
      'workspaceId': data.workspaceId,
      'lastLines': props.lastLines,
      'repos': props.repos
          .map((repo) => {'repo': repo.repo, 'branch': repo.branch})
          .toList(),
    };
  }

  Map<String, dynamic> _serializeEditor(EditorNodeData data) {
    final filePath = data.filePath;
    // Detect image files and send base64-encoded bytes.
    if (_isImagePath(filePath)) {
      try {
        final bytes = File(filePath).readAsBytesSync();
        return {
          'type': 'editor',
          'filePath': filePath,
          'language': '',
          'content': '',
          'tabs': const [],
          'imageBase64': base64Encode(bytes),
        };
      } catch (_) {
        // fall through to text serialization
      }
    }

    final props = buildEditorCardProps(
      data: data,
      editorState: fileEditorCubit?.state,
    );
    return {
      'type': 'editor',
      'filePath': props.filePath,
      'language': props.language,
      'content': props.content,
      'tabs': props.tabs
          .map((tab) => {'path': tab.path, 'isActive': tab.isActive})
          .toList(),
    };
  }

  static bool _isImagePath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico'}
        .contains(ext);
  }

  void _runAction(FutureOr<void> Function() action) {
    final result = action();
    if (result is Future<void>) {
      unawaited(result);
    }
  }

  /// Like [_runAction] but sets [isHandlingRemoteAction] while running,
  /// so the host viewport doesn't auto-pan for client-triggered events.
  void _runRemoteAction(FutureOr<void> Function() action) {
    _handlingRemoteAction = true;
    final result = action();
    if (result is Future<void>) {
      unawaited(
        result.whenComplete(() => _handlingRemoteAction = false),
      );
    } else {
      _handlingRemoteAction = false;
    }
  }

  /// Streams live terminal output to all connected browser guests.
  void _onTerminalData((String, String) event) {
    if (_server == null || _server!.clientCount == 0) return;
    final (sessionId, rawBytes) = event;
    // Find the agent node that owns this session.
    final node = mindMapCubit.state.nodes
        .whereType<AgentNodeData>()
        .cast<AgentNodeData?>()
        .firstWhere((n) => n!.session.id == sessionId, orElse: () => null);
    if (node == null) return;

    // Stream raw bytes so the web guest can render ANSI/TUI via its own
    // xterm Terminal instance (proper colors, box-drawing, scrollback).
    _server!.broadcastRaw(SyncMessage.terminalOutput(node.id, rawBytes));
  }

  /// Guest: send keyboard input for a terminal to the host.
  void sendTerminalInput(String nodeId, String data) {
    _client?.sendMessage(
      SyncMessage.terminalInput(nodeId, data, senderId: 'guest'),
    );
  }

  /// Guest: send a generic event to the host.
  void sendGuestEvent(String type, Map<String, dynamic> payload) {
    _client?.sendMessage(
      SyncMessage(type: type, payload: payload, senderId: 'guest'),
    );
  }

  /// Pushes the current full snapshot to all connected guests.
  void broadcastSnapshot() {
    if (_server == null || _server!.clientCount == 0) return;
    _server!.broadcastRaw(_buildSnapshot(mindMapCubit.state));
  }

  // ── Guest: received from host ─────────────────────────────────────────────

  void _onMessageFromHost(SyncMessage msg) {
    switch (msg.type) {
      case SyncMessage.kSnapshot:
        _applySnapshot(msg.payload);
      case SyncMessage.kDeltaMove:
        _applyMove(msg.payload);
      case SyncMessage.kDeltaResize:
        _applyResize(msg.payload);
      case SyncMessage.kDeltaToggle:
        _applyToggle(msg.payload);
      case SyncMessage.kNodeUpdate:
        final id = msg.payload['id'] as String;
        final content = (msg.payload['content'] as Map<String, dynamic>?) ?? {};
        mindMapCubit.updateNodeContent(id, content);
      case SyncMessage.kTerminalOutput:
        final id = msg.payload['id'] as String;
        final data = (msg.payload['data'] as String?) ?? '';
        GuestTerminalRegistry.instance.writeOutput(id, data);
      case SyncMessage.kPresence:
        // Full peer list from server — replace the peers map entirely.
        final list = (msg.payload['peers'] as List?) ?? [];
        final peers = <String, PeerInfo>{};
        for (final raw in list) {
          final m = raw as Map<String, dynamic>;
          final id    = m['id'] as String? ?? '';
          final name  = m['name'] as String? ?? 'Guest';
          final color = m['color'] as String? ?? '#60A5FA';
          if (id.isNotEmpty) peers[id] = PeerInfo(id: id, name: name, color: color);
        }
        emit(state.copyWith(peers: peers, peerCount: peers.length));
      case SyncMessage.kCursorMove:
        // Future: render peer cursor overlay.  No-op for now.
        break;
      case SyncMessage.kConnected:
        final id    = msg.payload['id'] as String? ?? '';
        final name  = msg.payload['name'] as String? ?? 'Guest';
        final color = msg.payload['color'] as String? ?? '#60A5FA';
        if (id.isEmpty) break;
        final peers = Map<String, PeerInfo>.from(state.peers)
          ..[id] = PeerInfo(id: id, name: name, color: color);
        emit(state.copyWith(peers: peers, peerCount: peers.length));
      case SyncMessage.kDisconnected:
        if (msg.payload['id'] == 'server') {
          disconnect();
        } else {
          final peers = Map<String, PeerInfo>.from(state.peers)
            ..remove(msg.payload['id']);
          emit(state.copyWith(peers: peers, peerCount: peers.length));
        }
    }
  }

  void _applySnapshot(Map<String, dynamic> p) {
    final posRaw = (p['positions'] as Map<String, dynamic>?) ?? {};
    final szRaw = (p['sizes'] as Map<String, dynamic>?) ?? {};
    final hidden = ((p['hidden'] as List?) ?? []).cast<String>().toSet();
    final hTypes = ((p['hiddenTypes'] as List?) ?? []).cast<String>().toSet();
    final connRaw = (p['connections'] as List?) ?? [];
    final ncRaw = (p['nodeContent'] as Map<String, dynamic>?) ?? {};
    final svRaw = (p['savedViews'] as Map<String, dynamic>?) ?? {};

    final positions = posRaw.map((k, v) {
      final l = (v as List).cast<num>();
      return MapEntry(k, Offset(l[0].toDouble(), l[1].toDouble()));
    });
    final sizes = szRaw.map((k, v) {
      final l = (v as List).cast<num>();
      return MapEntry(k, Size(l[0].toDouble(), l[1].toDouble()));
    });
    final connections = connRaw.map((raw) {
      final c = raw as Map<String, dynamic>;
      final style = ConnectorStyle.values.firstWhere(
        (s) => s.name == (c['style'] as String? ?? 'solid'),
        orElse: () => ConnectorStyle.solid,
      );
      return MindMapConnection(
        fromId: c['from'] as String,
        toId: c['to'] as String,
        style: style,
        color: Color(c['color'] as int),
      );
    }).toList();
    final nodeContent = ncRaw.map(
      (k, v) => MapEntry(k, (v as Map<String, dynamic>)),
    );
    final savedViews = svRaw.map(
      (k, v) => MapEntry(k, MindMapViewSnapshot.fromJson(v as Map<String, dynamic>)),
    );

    final nodeColors = ((p['nodeColors'] as Map<String, dynamic>?) ?? {}).map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    final remoteNodes = _deserializeRemoteNodes(nodeContent);

    mindMapCubit.applyRemoteSnapshot(
      positions: positions,
      sizes: sizes,
      hidden: hidden,
      hiddenTypes: hTypes,
      connections: connections,
      nodeContent: nodeContent,
      savedViews: savedViews,
      remoteNodes: remoteNodes,
      nodeColors: nodeColors,
    );
  }

  void _applyMove(Map<String, dynamic> p) => mindMapCubit.applyRemoteMove(
    p['id'] as String,
    Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
  );

  void _applyResize(Map<String, dynamic> p) => mindMapCubit.applyRemoteResize(
    p['id'] as String,
    Size((p['w'] as num).toDouble(), (p['h'] as num).toDouble()),
  );

  void _applyToggle(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final hidden = p['hidden'] as bool;
    if (hidden) {
      mindMapCubit.hideNode(id);
    } else {
      mindMapCubit.showNode(id);
    }
  }

  /// Deserialises remote node content into [MindMapNodeData] objects.
  /// Only handles node types that can be meaningfully reconstructed on a guest
  /// machine (e.g. [FilePanelNodeData]).  Native cubit-owned nodes (agent,
  /// workspace, session…) are omitted because each machine manages those via
  /// its own blocs.
  static List<MindMapNodeData> _deserializeRemoteNodes(
      Map<String, Map<String, dynamic>> nodeContent) {
    final result = <MindMapNodeData>[];
    for (final entry in nodeContent.entries) {
      final node = _deserializeNode(entry.key, entry.value);
      if (node != null) result.add(node);
    }
    return result;
  }

  static MindMapNodeData? _deserializeNode(
      String id, Map<String, dynamic> content) {
    switch (content['type'] as String?) {
      case 'panel':
        final filePath = content['filePath'] as String? ?? '';
        return filePath.isNotEmpty
            ? FilePanelNodeData(id: id, filePath: filePath)
            : null;
      default:
        return null;
    }
  }

  // ── Host: client messages ─────────────────────────────────────────────────

  /// Message-type → handler registry for [SyncMessage]s received from
  /// connected clients.  Unknown types are ignored (previous `default: break;`
  /// behaviour).
  late final Map<String, void Function(String, SyncMessage)>
      _clientMessageHandlers = {
    SyncMessage.kHello: _handleHello,
    SyncMessage.kDeltaMove: _handleDeltaMove,
    SyncMessage.kDeltaResize: _handleDeltaResize,
    SyncMessage.kDeltaToggle: _handleDeltaToggle,
    SyncMessage.kTerminalInput: _handleTerminalInput,
    'workspace_create': _handleWorkspaceCreate,
    'ws_add_folder': _handleWsAddFolder,
    'ws_create_session': _handleWsCreateSession,
    'run_start': _handleRunStart,
    'run_stop': _handleRunStop,
    'run_restart': _handleRunRestart,
    'file_select': _handleFileSelect,
    'tree_toggle': _handleTreeToggle,
    'tree_select': _handleTreeSelect,
    'editor_switch_tab': _handleEditorSwitchTab,
    'editor_save': _handleEditorSave,
    'editor_content_update': _handleEditorContentUpdate,
    'session_start': _handleSessionStart,
  };

  void _onClientMessage(String clientId, SyncMessage msg) {
    _clientMessageHandlers[msg.type]?.call(clientId, msg);
  }

  void _handleHello(String clientId, SyncMessage msg) {
    // Accept both wrapped {"payload":{"id":..}} and flat {"id":..} hello.
    final id =
        (msg.payload['id'] as String?) ??
        (msg.senderId.isNotEmpty ? msg.senderId : clientId);
    final name  = (msg.payload['name']  as String?) ?? 'Remote';
    final color = (msg.payload['color'] as String?) ?? '#60A5FA';
    final peers = Map<String, PeerInfo>.from(state.peers)
      ..[id] = PeerInfo(id: id, name: name, color: color);
    emit(state.copyWith(peers: peers, peerCount: peers.length));
    // Populate mind map from workspace/terminal state if not yet done,
    // then send the full snapshot to the newly connected client.
    _sendSnapshotAfterPopulate(clientId);
  }

  void _handleDeltaMove(String clientId, SyncMessage msg) {
    _applyMove(msg.payload);
  }

  void _handleDeltaResize(String clientId, SyncMessage msg) {
    _applyResize(msg.payload);
  }

  void _handleDeltaToggle(String clientId, SyncMessage msg) {
    _applyToggle(msg.payload);
  }

  void _handleTerminalInput(String clientId, SyncMessage msg) {
    // Forward keyboard input from browser guest to the actual PTY.
    final nodeId = msg.payload['id'] as String? ?? '';
    final data = msg.payload['data'] as String? ?? '';
    final sessionId = resolveTerminalSessionId(
      nodeId,
      mindMapCubit.state.nodes,
    );
    if (sessionId.isNotEmpty && data.isNotEmpty) {
      onTerminalInput?.call(sessionId, data);
    }
  }

  void _handleWorkspaceCreate(String clientId, SyncMessage msg) {
    if (onCreateWorkspace != null) {
      _runAction(() => onCreateWorkspace!(msg.payload));
    }
  }

  void _handleWsAddFolder(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final folderPath = msg.payload['path'] as String?;
    if (nodeId.isNotEmpty && onAddFolder != null) {
      _runAction(() => onAddFolder!(nodeId, path: folderPath));
    }
  }

  void _handleWsCreateSession(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onCreateSession != null) {
      _runAction(() => onCreateSession!(nodeId));
    }
  }

  void _handleRunStart(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onRunStart != null) {
      _runAction(() => onRunStart!(nodeId));
    }
  }

  void _handleRunStop(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onRunStop != null) {
      _runAction(() => onRunStop!(nodeId));
    }
  }

  void _handleRunRestart(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onRunRestart != null) {
      _runAction(() => onRunRestart!(nodeId));
    }
  }

  void _handleFileSelect(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final path = msg.payload['path'] as String? ?? '';
    if (nodeId.isNotEmpty && path.isNotEmpty && onFileSelect != null) {
      _runRemoteAction(() => onFileSelect!(nodeId, path));
    }
  }

  void _handleTreeToggle(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final path = msg.payload['path'] as String? ?? '';
    if (nodeId.isNotEmpty && path.isNotEmpty && onTreeToggle != null) {
      _runRemoteAction(() => onTreeToggle!(nodeId, path));
    }
  }

  void _handleTreeSelect(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final path = msg.payload['path'] as String? ?? '';
    if (nodeId.isNotEmpty && path.isNotEmpty && onTreeSelect != null) {
      _runRemoteAction(() => onTreeSelect!(nodeId, path));
    }
  }

  void _handleEditorSwitchTab(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final tabIndex = msg.payload['tabIndex'] as int?;
    if (nodeId.isNotEmpty &&
        tabIndex != null &&
        onEditorSwitchTab != null) {
      _runAction(() => onEditorSwitchTab!(nodeId, tabIndex));
    }
  }

  void _handleEditorSave(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onEditorSave != null) {
      _runRemoteAction(() => onEditorSave!(nodeId));
    }
  }

  void _handleEditorContentUpdate(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    final content = msg.payload['content'] as String? ?? '';
    if (nodeId.isNotEmpty && onEditorContentUpdate != null) {
      _runRemoteAction(() => onEditorContentUpdate!(nodeId, content));
    }
  }

  void _handleSessionStart(String clientId, SyncMessage msg) {
    final nodeId = msg.payload['id'] as String? ?? '';
    if (nodeId.isNotEmpty && onSessionStart != null) {
      _runAction(() => onSessionStart!(nodeId));
    }
  }

  /// Ensures the legacy collaboration backend has nodes populated from the
  /// current workspace and terminal state, then
  /// sends the full snapshot to [clientId].
  Future<void> _sendSnapshotAfterPopulate(String clientId) async {
    if (mindMapCubit.state.nodes.isEmpty) {
      await ensureNodesPopulated?.call();
    }
    _server?.sendTo(clientId, _buildSnapshot(mindMapCubit.state));

    // Replay raw terminal history so the guest renders the current TUI state
    // (Copilot CLI box, status bar, prompt, etc.), not just new output.
    for (final node in mindMapCubit.state.nodes.whereType<AgentNodeData>()) {
      final history = node.session.rawHistory();
      if (history.isEmpty) continue;
      _server?.sendTo(
        clientId,
        SyncMessage.terminalOutput(node.id, history),
      );
    }
  }

  @override
  Future<void> close() async {
    await stopHosting();
    await disconnect();
    await super.close();
  }
}
