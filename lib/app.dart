import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/handlers/assistant_handler.dart';
import 'package:yoloit/core/cli/handlers/calendar_handler.dart';
import 'package:yoloit/core/cli/handlers/chart_handler.dart';
import 'package:yoloit/core/cli/handlers/chat_handler.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/core/cli/handlers/files_handler.dart';
import 'package:yoloit/core/cli/handlers/filetree_handler.dart';
import 'package:yoloit/core/cli/handlers/kanban_handler.dart';
import 'package:yoloit/core/cli/handlers/note_handler.dart';
import 'package:yoloit/core/cli/handlers/playlist_handler.dart';
import 'package:yoloit/core/cli/handlers/run_configs_handler.dart';
import 'package:yoloit/core/cli/handlers/shape_handler.dart';
import 'package:yoloit/core/cli/handlers/sticky_note_handler.dart';
import 'package:yoloit/core/cli/handlers/table_handler.dart';
import 'package:yoloit/core/cli/handlers/terminal_handler.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/core/cli/handlers/webpage_handler.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/utils/git_init_prompt.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
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
import 'package:yoloit/features/runs/data/run_bridge.dart';
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
        BlocProvider(
          create: (_) {
            final cubit = RunCubit();
            RunBridge.instance.attach(cubit);
            return cubit;
          },
        ),
        BlocProvider(create: (_) => MindMapCubit()),
        BlocProvider(
          create: (_) => BoardCubit(historyStore: LocalBoardHistoryStore()),
        ),
        // Collaboration/guest mode still uses the legacy MindMap state model as
        // a compatibility backend. TODO(board-collab): migrate this to BoardCubit
        // and remove the remaining mindmap backend after Board View supports guests.
        BlocProvider(
          create: (ctx) {
            late final CollaborationCubit collaborationCubit;
            final mindMapCubit = ctx.read<MindMapCubit>();
            final workspaceCubit = ctx.read<WorkspaceCubit>();
            final terminalCubit = ctx.read<TerminalCubit>();
            final reviewCubit = ctx.read<ReviewCubit>();
            final fileEditorCubit = ctx.read<FileEditorCubit>();
            final runCubit = ctx.read<RunCubit>();
            Future<void> sync() => _syncMindMap(
              mindMapCubit,
              workspaceCubit.state,
              terminalCubit.state,
              reviewCubit.state,
              fileEditorCubit.state,
              runCubit.state,
              collaborationCubit: collaborationCubit,
              force: true,
            );
            void runAction(String nodeId, String action) => _handleRunAction(
              mindMapCubit,
              runCubit,
              workspaceCubit.state,
              terminalCubit.state,
              reviewCubit.state,
              fileEditorCubit.state,
              nodeId,
              collaborationCubit,
              action,
            );
            collaborationCubit = CollaborationCubit(
              mindMapCubit: mindMapCubit,
              onTerminalInput: PtyService.instance.write,
              reviewCubit: reviewCubit,
              fileEditorCubit: fileEditorCubit,
              listDirectory: listRepoDir,
              ensureNodesPopulated:
                  () => _populateMindMap(
                    mindMapCubit,
                    workspaceCubit.state,
                    terminalCubit.state,
                    reviewCubit.state,
                    fileEditorCubit.state,
                    runCubit.state,
                  ),
              onCreateWorkspace:
                  (payload) => _handleWorkspaceCreate(
                    mindMapCubit,
                    workspaceCubit,
                    terminalCubit,
                    reviewCubit,
                    fileEditorCubit,
                    runCubit,
                    collaborationCubit,
                    payload: payload,
                  ),
              onAddFolder:
                  (nodeId, {String? path}) => _handleAddFolder(
                    mindMapCubit,
                    workspaceCubit,
                    terminalCubit,
                    reviewCubit,
                    fileEditorCubit,
                    runCubit,
                    collaborationCubit,
                    nodeId,
                    path: path,
                  ),
              onCreateSession:
                  (nodeId) => _handleWorkspaceSessionCreate(
                    mindMapCubit,
                    workspaceCubit,
                    terminalCubit,
                    reviewCubit,
                    fileEditorCubit,
                    runCubit,
                    collaborationCubit,
                    nodeId,
                  ),
              onRunStart: (nodeId) => runAction(nodeId, 'start'),
              onRunStop: (nodeId) => runAction(nodeId, 'stop'),
              onRunRestart: (nodeId) => runAction(nodeId, 'restart'),
              onFileSelect:
                  (nodeId, path) => _handleFileSelect(
                    mindMapCubit,
                    fileEditorCubit,
                    workspaceCubit.state,
                    terminalCubit.state,
                    reviewCubit.state,
                    runCubit.state,
                    nodeId,
                    path,
                    collaborationCubit,
                  ),
              onTreeToggle: (_, path) {
                reviewCubit.toggleNode(path);
                return sync();
              },
              onTreeSelect:
                  (_, path) => _handleTreeSelect(
                    reviewCubit,
                    fileEditorCubit,
                    mindMapCubit,
                    workspaceCubit.state,
                    terminalCubit.state,
                    runCubit.state,
                    path,
                    collaborationCubit,
                  ),
              onEditorSwitchTab: (_, tabIndex) {
                fileEditorCubit.switchTab(tabIndex);
                return sync();
              },
              onEditorSave: (_) async {
                await fileEditorCubit.saveFile();
                return sync();
              },
              onEditorContentUpdate: (_, content) async {
                fileEditorCubit.updateContent(content);
                await fileEditorCubit.saveFile();
                return sync();
              },
              onSessionStart:
                  (nodeId) => _handleSessionStart(
                    mindMapCubit,
                    terminalCubit,
                    workspaceCubit.state,
                    reviewCubit.state,
                    fileEditorCubit.state,
                    runCubit.state,
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

  /// Populates the legacy collaboration canvas model with nodes derived from
  /// workspace and terminal state. TODO(board-collab): replace with BoardCubit
  /// snapshots once Board View supports browser guests.
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
      dir =
          path.startsWith('~')
              ? (Platform.environment['HOME'] ??
                      Platform.environment['USERPROFILE'] ??
                      '') +
                  path.substring(1)
              : path;
    } else {
      final dialogContext = navigatorKey.currentContext;
      if (dialogContext == null) return;
      dir = await BoardFilePicker.pickDirectory(
        dialogContext,
        title: 'Add folder to "${node.workspace.name}"',
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

    if (presetName != null &&
        presetName.isNotEmpty &&
        presetPath != null &&
        presetPath.isNotEmpty) {
      name = presetName;
      // Expand leading ~ to the home directory.
      folder =
          presetPath.startsWith('~')
              ? (Platform.environment['HOME'] ??
                      Platform.environment['USERPROFILE'] ??
                      '') +
                  presetPath.substring(1)
              : presetPath;
    } else {
      // Native host path: show macOS dialogs.
      final dialogContext = navigatorKey.currentContext;
      if (dialogContext == null) return;

      final controller = TextEditingController();
      final pickedName = await showDialog<String>(
        context: dialogContext,
        builder: (ctx) {
          final colors = ctx.appColors;
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.border),
            ),
            title: Text(
              'New Workspace',
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Workspace name',
                hintStyle: TextStyle(color: colors.textMuted),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: Text(
                  'Pick folder →',
                  style: TextStyle(color: colors.primary),
                ),
              ),
            ],
          );
        },
      );
      controller.dispose();
      if (pickedName == null || pickedName.isEmpty) return;

      final pickedFolder = await BoardFilePicker.pickDirectory(
        dialogContext,
        title: 'Pick a folder for "$pickedName"',
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
      builder: (ctx) {
        final colors = ctx.appColors;
        return SimpleDialog(
          backgroundColor: colors.surface,
          title: Text(
            'New Session',
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          children: [
            for (final agentType in AgentType.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, agentType),
                child: Text(
                  agentType.displayName,
                  style: TextStyle(color: colors.terminalText),
                ),
              ),
          ],
        );
      },
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
        _startCliServer();
      }
    });
  }

  void _startCliServer() {
    final cubit = context.read<BoardCubit>();
    final terminalCubit = context.read<TerminalCubit>();
    final server = CliServer.instance;
    // Register all panel CLI handlers
    server.registerPanelHandler(const NoteCliHandler());
    server.registerPanelHandler(const StickyNoteCliHandler());
    server.registerPanelHandler(const ShapeCliHandler());
    server.registerPanelHandler(ChatCliHandler());
    server.registerPanelHandler(const KanbanCliHandler());
    server.registerPanelHandler(const WebpageCliHandler());
    server.registerPanelHandler(const PlaylistCliHandler());
    server.registerPanelHandler(const ChecklistCliHandler());
    server.registerPanelHandler(const CodeSnippetCliHandler());
    server.registerPanelHandler(const FilesCliHandler());
    server.registerPanelHandler(const FilePreviewCliHandler());
    server.registerPanelHandler(const RunConfigsCliHandler());
    server.registerPanelHandler(
      const RunConfigsCliHandler(panelTypeId: 'board.run'),
    );
    server.registerPanelHandler(const TerminalCliHandler());
    server.registerPanelHandler(const FileTreeCliHandler());
    server.registerPanelHandler(const AssistantCliHandler());
    server.registerPanelHandler(const TimerCliHandler());
    server.registerPanelHandler(const CalendarCliHandler());
    server.registerPanelHandler(const TableCliHandler());
    server.registerPanelHandler(const ChartCliHandler());
    server.registerPanelHandler(const CustomWidgetCliHandler());
    server.start(cubit, terminalCubit: terminalCubit);
    // Wire service managers to BoardCubit for headless state updates
    TimerManager.instance.setCubit(cubit);
    WidgetEngineManager.instance.setCubit(cubit);
  }

  @override
  Widget build(BuildContext context) => const MainShell();
}
