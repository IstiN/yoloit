import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/utils/git_init_prompt.dart';
import 'package:yoloit/features/collaboration/bloc/collaboration_cubit.dart';
import 'package:yoloit/features/collaboration/desktop/repo_directory_listing.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/model/mindmap_graph_builder.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/ui/shell/main_shell.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => WorkspaceCubit()),
        BlocProvider(create: (_) => TerminalCubit()),
        BlocProvider(create: (_) => ReviewCubit()),
        BlocProvider(create: (_) => FileEditorCubit()),
        BlocProvider(create: (_) => RunCubit()),
        BlocProvider(create: (_) => MindMapCubit()),
        // CollaborationCubit must come after MindMapCubit so it can read it.
        BlocProvider(
          create: (ctx) {
            late final CollaborationCubit collaborationCubit;
            collaborationCubit = CollaborationCubit(
              mindMapCubit: ctx.read<MindMapCubit>(),
              onTerminalInput: PtyService.instance.write,
              reviewCubit: ctx.read<ReviewCubit>(),
              fileEditorCubit: ctx.read<FileEditorCubit>(),
              listDirectory: listRepoDir,
              ensureNodesPopulated: () => _populateMindMap(
                ctx.read<MindMapCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<FileEditorCubit>().state,
                ctx.read<RunCubit>().state,
              ),
              onCreateWorkspace: (payload) => _handleWorkspaceCreate(
                ctx.read<MindMapCubit>(),
                ctx.read<WorkspaceCubit>(),
                ctx.read<TerminalCubit>(),
                ctx.read<ReviewCubit>(),
                ctx.read<FileEditorCubit>(),
                ctx.read<RunCubit>(),
                collaborationCubit,
                payload: payload,
              ),
              onAddFolder: (nodeId, {String? path}) => _handleAddFolder(
                ctx.read<MindMapCubit>(),
                ctx.read<WorkspaceCubit>(),
                ctx.read<TerminalCubit>(),
                ctx.read<ReviewCubit>(),
                ctx.read<FileEditorCubit>(),
                ctx.read<RunCubit>(),
                collaborationCubit,
                nodeId,
                path: path,
              ),
              onCreateSession: (nodeId) => _handleWorkspaceSessionCreate(
                ctx.read<MindMapCubit>(),
                ctx.read<WorkspaceCubit>(),
                ctx.read<TerminalCubit>(),
                ctx.read<ReviewCubit>(),
                ctx.read<FileEditorCubit>(),
                ctx.read<RunCubit>(),
                collaborationCubit,
                nodeId,
              ),
              onRunStart: (nodeId) => _handleRunAction(
                ctx.read<MindMapCubit>(),
                ctx.read<RunCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<FileEditorCubit>().state,
                nodeId,
                collaborationCubit,
                'start',
              ),
              onRunStop: (nodeId) => _handleRunAction(
                ctx.read<MindMapCubit>(),
                ctx.read<RunCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<FileEditorCubit>().state,
                nodeId,
                collaborationCubit,
                'stop',
              ),
              onRunRestart: (nodeId) => _handleRunAction(
                ctx.read<MindMapCubit>(),
                ctx.read<RunCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<FileEditorCubit>().state,
                nodeId,
                collaborationCubit,
                'restart',
              ),
              onFileSelect: (nodeId, path) => _handleFileSelect(
                ctx.read<MindMapCubit>(),
                ctx.read<FileEditorCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<RunCubit>().state,
                nodeId,
                path,
                collaborationCubit,
              ),
              onTreeToggle: (_, path) {
                ctx.read<ReviewCubit>().toggleNode(path);
                return _syncMindMap(
                  ctx.read<MindMapCubit>(),
                  ctx.read<WorkspaceCubit>().state,
                  ctx.read<TerminalCubit>().state,
                  ctx.read<ReviewCubit>().state,
                  ctx.read<FileEditorCubit>().state,
                  ctx.read<RunCubit>().state,
                  collaborationCubit: collaborationCubit,
                  force: true,
                );
              },
              onTreeSelect: (_, path) => _handleTreeSelect(
                ctx.read<ReviewCubit>(),
                ctx.read<FileEditorCubit>(),
                ctx.read<MindMapCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<TerminalCubit>().state,
                ctx.read<RunCubit>().state,
                path,
                collaborationCubit,
              ),
              onEditorSwitchTab: (_, tabIndex) {
                ctx.read<FileEditorCubit>().switchTab(tabIndex);
                return _syncMindMap(
                  ctx.read<MindMapCubit>(),
                  ctx.read<WorkspaceCubit>().state,
                  ctx.read<TerminalCubit>().state,
                  ctx.read<ReviewCubit>().state,
                  ctx.read<FileEditorCubit>().state,
                  ctx.read<RunCubit>().state,
                  collaborationCubit: collaborationCubit,
                  force: true,
                );
              },
              onEditorSave: (_) async {
                await ctx.read<FileEditorCubit>().saveFile();
                await _syncMindMap(
                  ctx.read<MindMapCubit>(),
                  ctx.read<WorkspaceCubit>().state,
                  ctx.read<TerminalCubit>().state,
                  ctx.read<ReviewCubit>().state,
                  ctx.read<FileEditorCubit>().state,
                  ctx.read<RunCubit>().state,
                  collaborationCubit: collaborationCubit,
                  force: true,
                );
              },
              onEditorContentUpdate: (_, content) async {
                ctx.read<FileEditorCubit>().updateContent(content);
                await ctx.read<FileEditorCubit>().saveFile();
                await _syncMindMap(
                  ctx.read<MindMapCubit>(),
                  ctx.read<WorkspaceCubit>().state,
                  ctx.read<TerminalCubit>().state,
                  ctx.read<ReviewCubit>().state,
                  ctx.read<FileEditorCubit>().state,
                  ctx.read<RunCubit>().state,
                  collaborationCubit: collaborationCubit,
                  force: true,
                );
              },
              onSessionStart: (nodeId) => _handleSessionStart(
                ctx.read<MindMapCubit>(),
                ctx.read<TerminalCubit>(),
                ctx.read<WorkspaceCubit>().state,
                ctx.read<ReviewCubit>().state,
                ctx.read<FileEditorCubit>().state,
                ctx.read<RunCubit>().state,
                collaborationCubit,
                nodeId,
              ),
            );
            return collaborationCubit;
          },
        ),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<WorkspaceCubit, WorkspaceState>(
            listener: (context, _) => _scheduleMindMapSync(context),
          ),
          BlocListener<TerminalCubit, TerminalState>(
            listener: (context, _) => _scheduleMindMapSync(context),
          ),
          BlocListener<ReviewCubit, ReviewState>(
            listener: (context, _) => _scheduleMindMapSync(context),
          ),
          BlocListener<FileEditorCubit, FileEditorState>(
            listener: (context, _) => _scheduleMindMapSync(context),
          ),
          BlocListener<RunCubit, RunState>(
            listener: (context, _) => _scheduleMindMapSync(context),
          ),
        ],
        child: ListenableBuilder(
          listenable: ThemeManager.instance,
          builder: (context, _) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'yoloit',
              debugShowCheckedModeBanner: false,
              theme: ThemeManager.instance.theme,
              home: const _AutoHostShell(),
            );
          },
        ),
      ),
    );
  }

  static void _scheduleMindMapSync(BuildContext context) {
    unawaited(
      _syncMindMap(
        context.read<MindMapCubit>(),
        context.read<WorkspaceCubit>().state,
        context.read<TerminalCubit>().state,
        context.read<ReviewCubit>().state,
        context.read<FileEditorCubit>().state,
        context.read<RunCubit>().state,
        collaborationCubit: context.read<CollaborationCubit>(),
        force: true,
      ),
    );
  }

  /// Populates [mindMapCubit] with nodes derived from workspace and terminal
  /// state so that browser guests see a meaningful canvas even when the user
  /// has not yet opened the Map View in the macOS app.
  static Future<void> _populateMindMap(
    MindMapCubit mindMapCubit,
    WorkspaceState wsState,
    TerminalState termState,
    ReviewState reviewState,
    FileEditorState editorState,
    RunState runState, {
    bool force = false,
  }) async {
    if (!force &&
        mindMapCubit.state.positions.isNotEmpty &&
        mindMapCubit.state.nodes.isNotEmpty) {
      return;
    }

    await _syncMindMap(
      mindMapCubit,
      wsState,
      termState,
      reviewState,
      editorState,
      runState,
      force: true,
    );
  }

  static Future<void> _syncMindMap(
    MindMapCubit mindMapCubit,
    WorkspaceState wsState,
    TerminalState termState,
    ReviewState reviewState,
    FileEditorState editorState,
    RunState runState, {
    CollaborationCubit? collaborationCubit,
    required bool force,
  }) async {
    if (!force &&
        mindMapCubit.state.positions.isNotEmpty &&
        mindMapCubit.state.nodes.isNotEmpty) {
      return;
    }
    final graph = buildMindMapGraph(
      wsState: wsState,
      termState: termState,
      reviewState: reviewState,
      editorState: editorState,
      runState: runState,
    );
    if (graph.nodes.isEmpty) return;
    final pluginNodes = mindMapCubit.state.nodes
        .whereType<MindMapPluginNodeData>()
        .where((plugin) => graph.nodes.every((node) => node.id != plugin.id))
        .toList(growable: false);
    final pluginIds = pluginNodes.map((node) => node.id).toSet();
    final pluginConnections = mindMapCubit.state.connections
        .where(
          (connection) =>
              pluginIds.contains(connection.fromId) ||
              pluginIds.contains(connection.toId),
        )
        .where(
          (connection) => graph.conns.every(
            (existing) =>
                existing.fromId != connection.fromId ||
                existing.toId != connection.toId ||
                existing.style != connection.style ||
                existing.color != connection.color,
          ),
        )
        .toList(growable: false);
    mindMapCubit.updateNodes(
      [...graph.nodes, ...pluginNodes],
      [...graph.conns, ...pluginConnections],
    );
    await Future<void>.delayed(Duration.zero);
    collaborationCubit?.broadcastSnapshot();
  }

  static Future<void> _handleSessionStart(
    MindMapCubit mindMapCubit,
    TerminalCubit terminalCubit,
    WorkspaceState wsState,
    ReviewState reviewState,
    FileEditorState editorState,
    RunState runState,
    CollaborationCubit collaborationCubit,
    String nodeId,
  ) async {
    final node = _findNode<AgentNodeData>(mindMapCubit, nodeId);
    if (node == null) return;
    await terminalCubit.spawnSession(
      type: node.session.type,
      workspacePath: node.session.workspacePath,
      workspaceId: node.session.workspaceId,
      savedSessionId: node.session.id,
      isRestore: true,
      worktreeContexts: node.session.worktreeContexts,
    );
    await _syncMindMap(
      mindMapCubit,
      wsState,
      terminalCubit.state,
      reviewState,
      editorState,
      runState,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleAddFolder(
    MindMapCubit mindMapCubit,
    WorkspaceCubit workspaceCubit,
    TerminalCubit terminalCubit,
    ReviewCubit reviewCubit,
    FileEditorCubit fileEditorCubit,
    RunCubit runCubit,
    CollaborationCubit collaborationCubit,
    String nodeId, {
    String? path,
  }) async {
    final node = _findNode<WorkspaceNodeData>(mindMapCubit, nodeId);
    if (node == null) return;

    final String? dir;
    if (path != null && path.isNotEmpty) {
      // Web client provided the path directly — expand ~ if needed.
      dir = path.startsWith('~')
          ? (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '') + path.substring(1)
          : path;
    } else {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Add folder to "${node.workspace.name}"',
      );
    }
    if (dir == null) return;

    await workspaceCubit.addPathToWorkspace(node.workspace.id, dir);
    await _syncMindMap(
      mindMapCubit,
      workspaceCubit.state,
      terminalCubit.state,
      reviewCubit.state,
      fileEditorCubit.state,
      runCubit.state,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleWorkspaceCreate(
    MindMapCubit mindMapCubit,
    WorkspaceCubit workspaceCubit,
    TerminalCubit terminalCubit,
    ReviewCubit reviewCubit,
    FileEditorCubit fileEditorCubit,
    RunCubit runCubit,
    CollaborationCubit collaborationCubit, {
    Map<String, dynamic> payload = const {},
  }) async {
    // Web clients pass name+path in the payload so the host doesn't need
    // to open a native macOS dialog.
    final presetName = payload['name'] as String?;
    final presetPath = payload['path'] as String?;

    final String name;
    final String folder;

    if (presetName != null && presetName.isNotEmpty &&
        presetPath != null && presetPath.isNotEmpty) {
      name = presetName;
      // Expand leading ~ to the home directory.
      folder = presetPath.startsWith('~')
          ? (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '') + presetPath.substring(1)
          : presetPath;
    } else {
      // Native host path: show macOS dialogs.
      final dialogContext = navigatorKey.currentContext;
      if (dialogContext == null) return;

      final controller = TextEditingController();
      final pickedName = await showDialog<String>(
        context: dialogContext,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF12151C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2A3040)),
          ),
          title: const Text(
            'New Workspace',
            style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 14),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFFE8E8FF)),
            decoration: const InputDecoration(
              hintText: 'Workspace name',
              hintStyle: TextStyle(color: Color(0xFF6B7898)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B7898)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(
                'Pick folder →',
                style: TextStyle(color: Color(0xFF7C6BFF)),
              ),
            ),
          ],
        ),
      );
      controller.dispose();
      if (pickedName == null || pickedName.isEmpty) return;

      final pickedFolder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Pick a folder for "$pickedName"',
      );
      if (pickedFolder == null) return;
      name = pickedName;
      folder = pickedFolder;
    }

    // Only prompt git init for native (host) flow — remote clients
    // already have a BuildContext via app.dart dialogContext.
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await maybePromptGitInit(ctx, folder);
    }

    await workspaceCubit.addWorkspace(folder, customName: name);
    await _syncMindMap(
      mindMapCubit,
      workspaceCubit.state,
      terminalCubit.state,
      reviewCubit.state,
      fileEditorCubit.state,
      runCubit.state,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleWorkspaceSessionCreate(
    MindMapCubit mindMapCubit,
    WorkspaceCubit workspaceCubit,
    TerminalCubit terminalCubit,
    ReviewCubit reviewCubit,
    FileEditorCubit fileEditorCubit,
    RunCubit runCubit,
    CollaborationCubit collaborationCubit,
    String nodeId,
  ) async {
    final node = _findNode<WorkspaceNodeData>(mindMapCubit, nodeId);
    if (node == null || node.workspace.paths.isEmpty) return;

    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) return;

    final type = await showDialog<AgentType>(
      context: dialogContext,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF12151C),
        title: const Text(
          'New Session',
          style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 14),
        ),
        children: [
          for (final agentType in AgentType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, agentType),
              child: Text(
                agentType.displayName,
                style: const TextStyle(color: Color(0xFFCECEEE)),
              ),
            ),
        ],
      ),
    );
    if (type == null) return;

    await terminalCubit.spawnSession(
      type: type,
      workspacePath: node.workspace.paths.first,
      workspaceId: node.workspace.id,
    );
    await _syncMindMap(
      mindMapCubit,
      workspaceCubit.state,
      terminalCubit.state,
      reviewCubit.state,
      fileEditorCubit.state,
      runCubit.state,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleTreeSelect(
    ReviewCubit reviewCubit,
    FileEditorCubit fileEditorCubit,
    MindMapCubit mindMapCubit,
    WorkspaceState wsState,
    TerminalState termState,
    RunState runState,
    String path,
    CollaborationCubit collaborationCubit,
  ) async {
    await reviewCubit.selectFile(path);
    await fileEditorCubit.openFile(path);
    await _syncMindMap(
      mindMapCubit,
      wsState,
      termState,
      reviewCubit.state,
      fileEditorCubit.state,
      runState,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleFileSelect(
    MindMapCubit mindMapCubit,
    FileEditorCubit fileEditorCubit,
    WorkspaceState wsState,
    TerminalState termState,
    ReviewState reviewState,
    RunState runState,
    String nodeId,
    String path,
    CollaborationCubit collaborationCubit,
  ) async {
    final node = _findNode<FilesNodeData>(mindMapCubit, nodeId);
    if (node == null) return;
    await fileEditorCubit.openDiff(path, node.repoPath);
    await _syncMindMap(
      mindMapCubit,
      wsState,
      termState,
      reviewState,
      fileEditorCubit.state,
      runState,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static Future<void> _handleRunAction(
    MindMapCubit mindMapCubit,
    RunCubit runCubit,
    WorkspaceState wsState,
    TerminalState termState,
    ReviewState reviewState,
    FileEditorState editorState,
    String nodeId,
    CollaborationCubit collaborationCubit,
    String action,
  ) async {
    final node = _findNode<RunNodeData>(mindMapCubit, nodeId);
    if (node == null) return;
    switch (action) {
      case 'start':
        await runCubit.startRun(node.session.config);
      case 'stop':
        runCubit.stopRun(node.session.id);
      case 'restart':
        if (node.session.status == RunStatus.running) {
          runCubit.stopRun(node.session.id);
        }
        await runCubit.startRun(node.session.config);
    }
    await _syncMindMap(
      mindMapCubit,
      wsState,
      termState,
      reviewState,
      editorState,
      runCubit.state,
      collaborationCubit: collaborationCubit,
      force: true,
    );
  }

  static T? _findNode<T extends MindMapNodeData>(
    MindMapCubit mindMapCubit,
    String nodeId,
  ) {
    for (final node in mindMapCubit.state.nodes.whereType<T>()) {
      if (node.id == nodeId) return node;
    }
    return null;
  }
}

/// Wraps [MainShell] and auto-starts the collaboration server on the first
/// frame so the host is always reachable via browser without a manual tap.
class _AutoHostShell extends StatefulWidget {
  const _AutoHostShell();

  @override
  State<_AutoHostShell> createState() => _AutoHostShellState();
}

class _AutoHostShellState extends State<_AutoHostShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CollaborationCubit>().startHosting();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const MainShell();
}
