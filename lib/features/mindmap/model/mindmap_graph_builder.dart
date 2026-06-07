import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';

import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

/// Reads the current branch name from a git directory (main repo or worktree)
/// by inspecting the HEAD file — no subprocess, instant.
String _branchFromHead(String headPath) {
  try {
    final head = File(headPath).readAsStringSync().trim();
    if (head.startsWith('ref: refs/heads/')) {
      return head.substring('ref: refs/heads/'.length);
    }
    return head.length >= 7 ? head.substring(0, 7) : head;
  } catch (_) {
    return 'HEAD';
  }
}

void _addRepoAndBranch({
  required List<MindMapNodeData> nodes,
  required List<MindMapConnection> conns,
  required String agentNodeId,
  required String repoNodeId,
  required String branchNodeId,
  required String sessionId,
  required String repoPath,
  required String repoName,
  required String branch,
  required AppColorScheme palette,
}) {
  if (!nodes.any((node) => node.id == repoNodeId)) {
    nodes.add(
      RepoNodeData(
        id: repoNodeId,
        sessionId: sessionId,
        repoPath: repoPath,
        repoName: repoName,
        branch: branch,
      ),
    );
  }
  conns.add(
    MindMapConnection(
      fromId: agentNodeId,
      toId: repoNodeId,
      style: ConnectorStyle.solid,
      color: palette.accentBlue.withValues(alpha: 0.35),
    ),
  );

  if (!nodes.any((node) => node.id == branchNodeId)) {
    nodes.add(
      BranchNodeData(
        id: branchNodeId,
        repoId: repoNodeId,
        repoName: repoName,
        branch: branch,
        commitHash: '',
      ),
    );
  }
  conns.add(
    MindMapConnection(
      fromId: repoNodeId,
      toId: branchNodeId,
      style: ConnectorStyle.dashed,
      color: palette.primary.withValues(alpha: 0.35),
    ),
  );
}

String _branchFromDir(String dirPath) {
  try {
    // Main repo: .git is a directory → HEAD lives inside it.
    final dotGitDir = Directory('$dirPath/.git');
    if (dotGitDir.existsSync()) {
      return _branchFromHead('$dirPath/.git/HEAD');
    }
    // Worktree: .git is a file containing "gitdir: <absolute-path>"
    final dotGitFile = File('$dirPath/.git');
    if (dotGitFile.existsSync()) {
      final content = dotGitFile.readAsStringSync().trim();
      if (content.startsWith('gitdir: ')) {
        var gitdir = content.substring('gitdir: '.length);
        if (!gitdir.startsWith('/')) {
          gitdir = p.normalize('$dirPath/$gitdir');
        }
        return _branchFromHead('$gitdir/HEAD');
      }
    }
  } catch (_) {}
  return 'HEAD';
}

({List<MindMapNodeData> nodes, List<MindMapConnection> conns})
buildMindMapGraph({
  required WorkspaceState wsState,
  required TerminalState termState,
  required ReviewState reviewState,
  required FileEditorState editorState,
  required RunState runState,
  AppColorScheme? colors,
}) {
  final nodes = <MindMapNodeData>[];
  final conns = <MindMapConnection>[];
  final palette = colors ?? AppColorScheme.fromAccent(Colors.deepPurpleAccent);

  if (wsState is! WorkspaceLoaded) return (nodes: nodes, conns: conns);

  for (final ws in wsState.workspaces) {
    final wsNodeId = 'ws:${ws.id}';
    nodes.add(WorkspaceNodeData(id: wsNodeId, workspace: ws));

    final sessions =
        termState is TerminalLoaded
            ? termState.allSessions.where((s) {
              if (s.workspaceId != null) return s.workspaceId == ws.id;
              return ws.paths.any((p2) => s.workspacePath.startsWith(p2));
            }).toList()
            : <AgentSession>[];

    for (final session in sessions) {
      final agentNodeId = 'agent:${session.id}';

      // Determine the branch this session is actually on.
      // For worktree sessions read from the worktree path's HEAD file.
      final sessionWtFirst = session.worktreeContexts?.values.firstOrNull;
      final sessionBranch =
          sessionWtFirst != null
              ? _branchFromDir(sessionWtFirst)
              : _branchFromDir(ws.paths.isNotEmpty ? ws.paths.first : '');

      nodes.add(
        AgentNodeData(
          id: agentNodeId,
          session: session,
          workspaceId: ws.id,
          workspacePaths: ws.paths,
          workspaceBranch: sessionBranch,
        ),
      );

      final isLive = session.status == AgentStatus.live;
      final agentConnStyle =
          isLive ? ConnectorStyle.animated : ConnectorStyle.solid;
      final agentColor = isLive ? palette.accentGreen : palette.accentBlue;

      conns.add(
        MindMapConnection(
          fromId: wsNodeId,
          toId: agentNodeId,
          style: agentConnStyle,
          color: agentColor.withAlpha(100),
        ),
      );

      final repoPaths = <String, ({String effectivePath, String branch})>{};
      final sessionWt = session.worktreeContexts;
      if (sessionWt != null && sessionWt.isNotEmpty) {
        // worktreeContexts: originalRepoPath → worktreePath
        // Use the worktreePath as the effective directory for file tree / diff
        // and read the real branch from the HEAD file.
        for (final e in sessionWt.entries) {
          final worktreePath = e.value;
          repoPaths[e.key] = (
            effectivePath: worktreePath,
            branch: _branchFromDir(worktreePath),
          );
        }
      } else {
        for (final repoPath in ws.paths) {
          repoPaths[repoPath] = (
            effectivePath: repoPath,
            branch: _branchFromDir(repoPath),
          );
        }
      }

      for (final entry in repoPaths.entries) {
        final originalRepoPath = entry.key;
        final effectivePath = entry.value.effectivePath;
        final branchName = entry.value.branch;
        final repoName = p.basename(originalRepoPath);
        // Include branch in the ID so worktrees on the same repo but different
        // branches each get their own set of nodes (repo → branch → tree → diff).
        final repoNodeId = 'repo:${ws.id}:$originalRepoPath:$branchName';
        final branchNodeId = 'branch:${ws.id}:$originalRepoPath:$branchName';

        _addRepoAndBranch(
          nodes: nodes,
          conns: conns,
          agentNodeId: agentNodeId,
          repoNodeId: repoNodeId,
          branchNodeId: branchNodeId,
          sessionId: session.id,
          repoPath: effectivePath,
          repoName: repoName,
          branch: branchName,
          palette: palette,
        );
      }
    }
  }

  if (termState is TerminalLoaded) {
    final existingAgents =
        nodes
            .whereType<AgentNodeData>()
            .map((agent) => agent.session.id)
            .toSet();
    for (final session in termState.allSessions) {
      if (existingAgents.contains(session.id)) continue;
      final agentNodeId = 'agent:${session.id}';
      final matchedWs =
          wsState.workspaces
              .where(
                (workspace) =>
                    workspace.id == session.workspaceId ||
                    workspace.paths.any(
                      (repoPath) => session.workspacePath.startsWith(repoPath),
                    ),
              )
              .firstOrNull;
      nodes.add(
        AgentNodeData(
          id: agentNodeId,
          session: session,
          workspaceId: session.workspaceId ?? '',
          workspacePaths: matchedWs?.paths ?? const [],
          workspaceBranch: matchedWs?.gitBranch,
        ),
      );

      final wt =
          session.worktreeContexts?.isNotEmpty == true
              ? session.worktreeContexts!
              : (matchedWs != null && matchedWs.paths.isNotEmpty
                  ? {
                    for (final repoPath in matchedWs.paths)
                      repoPath: matchedWs.gitBranch ?? 'main',
                  }
                  : {session.workspacePath: 'main'});
      for (final entry in wt.entries) {
        final repoPath = entry.key;
        final branchRef = entry.value;
        final repoName = p.basename(repoPath);
        final repoNodeId = 'repo:orphan:$repoPath';
        final branchNodeId = 'branch:orphan:$repoPath';
        _addRepoAndBranch(
          nodes: nodes,
          conns: conns,
          agentNodeId: agentNodeId,
          repoNodeId: repoNodeId,
          branchNodeId: branchNodeId,
          sessionId: session.id,
          repoPath: repoPath,
          repoName: repoName,
          branch: p.basename(branchRef),
          palette: palette,
        );
      }
    }
  }

  final repoNodes = nodes.whereType<RepoNodeData>().toList();
  for (final repo in repoNodes) {
    // Use repoPath + branch in the ID so worktrees on the same repo path but
    // different branches get separate Tree and Diff panels.
    final treeId = 'tree:${repo.repoPath}:${repo.branch}';
    final diffId = 'diff:${repo.repoPath}:${repo.branch}';
    if (nodes.any((node) => node.id == treeId)) continue;
    nodes.add(
      FileTreeNodeData(
        id: treeId,
        workspaceId: '',
        repoPath: repo.repoPath,
        repoName: '${repo.repoName} · ${repo.branch}',
      ),
    );
    conns.add(
      MindMapConnection(
        fromId: repo.id,
        toId: treeId,
        style: ConnectorStyle.dashed,
        color: palette.accentGreen.withValues(alpha: 0.38),
      ),
    );
    if (!nodes.any((node) => node.id == diffId)) {
      nodes.add(
        DiffNodeData(
          id: diffId,
          workspaceId: '',
          repoPath: repo.repoPath,
          repoName: '${repo.repoName} · ${repo.branch}',
        ),
      );
      conns.add(
        MindMapConnection(
          fromId: treeId,
          toId: diffId,
          style: ConnectorStyle.dashed,
          color: palette.primary.withValues(alpha: 0.38),
        ),
      );
    }
  }

  for (final ws in wsState.workspaces) {
    for (final path in ws.paths) {
      final treeId = 'tree:$path';
      final diffId = 'diff:$path';
      if (nodes.any((node) => node.id == treeId)) continue;
      nodes.add(
        FileTreeNodeData(
          id: treeId,
          workspaceId: ws.id,
          repoPath: path,
          repoName: p.basename(path),
        ),
      );
      conns.add(
        MindMapConnection(
          fromId: 'ws:${ws.id}',
          toId: treeId,
          style: ConnectorStyle.dashed,
          color: palette.accentGreen.withValues(alpha: 0.31),
        ),
      );
      if (!nodes.any((node) => node.id == diffId)) {
        nodes.add(
          DiffNodeData(
            id: diffId,
            workspaceId: ws.id,
            repoPath: path,
            repoName: p.basename(path),
          ),
        );
        conns.add(
          MindMapConnection(
            fromId: treeId,
            toId: diffId,
            style: ConnectorStyle.dashed,
            color: palette.primary.withValues(alpha: 0.31),
          ),
        );
      }
    }
  }

  if (editorState.isVisible && editorState.tabs.isNotEmpty) {
    final idx = editorState.activeIndex.clamp(0, editorState.tabs.length - 1);
    final activeTab = editorState.tabs[idx];
    const editorId = 'editor:active';
    nodes.add(
      EditorNodeData(
        id: editorId,
        filePath: activeTab.filePath,
        content: activeTab.content ?? '',
        language: _detectLanguage(activeTab.filePath),
      ),
    );
    final filePath = activeTab.filePath;
    final matchingTree = nodes
        .whereType<FileTreeNodeData>()
        .where(
          (tree) =>
              tree.repoPath != null && filePath.startsWith(tree.repoPath!),
        )
        .fold<FileTreeNodeData?>(
          null,
          (best, tree) =>
              best == null ||
                      (tree.repoPath?.length ?? 0) >
                          (best.repoPath?.length ?? 0)
                  ? tree
                  : best,
        );
    if (matchingTree != null) {
      conns.add(
        MindMapConnection(
          fromId: matchingTree.id,
          toId: editorId,
          style: ConnectorStyle.dashed,
          color: palette.accentBlue.withValues(alpha: 0.44),
        ),
      );
    }
  }

  if (runState.sessions.isNotEmpty) {
    for (final runSession in runState.sessions) {
      final matchingWs =
          wsState.workspaces
              .where(
                (workspace) => workspace.paths.any(
                  (repoPath) => runSession.workspacePath.startsWith(repoPath),
                ),
              )
              .firstOrNull;
      final runId = 'run:${runSession.id}';
      nodes.add(
        RunNodeData(
          id: runId,
          session: runSession,
          workspaceId: matchingWs?.id ?? '',
        ),
      );
      final matchingAgent =
          nodes
              .whereType<AgentNodeData>()
              .where((agent) => agent.workspaceId == (matchingWs?.id ?? ''))
              .firstOrNull;
      conns.add(
        MindMapConnection(
          fromId: matchingAgent?.id ?? 'ws:${matchingWs?.id ?? ''}',
          toId: runId,
          style:
              runSession.status == RunStatus.running
                  ? ConnectorStyle.animated
                  : ConnectorStyle.solid,
          color:
              runSession.status == RunStatus.running
                  ? palette.accentGreen.withValues(alpha: 0.67)
                  : palette.accentBlue.withValues(alpha: 0.5),
        ),
      );
    }
  }

  return (nodes: nodes, conns: conns);
}

String _detectLanguage(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.dart' => 'Dart',
    '.ts' => 'TypeScript',
    '.tsx' => 'TSX',
    '.js' => 'JavaScript',
    '.py' => 'Python',
    '.go' => 'Go',
    '.rs' => 'Rust',
    '.yaml' || '.yml' => 'YAML',
    '.json' => 'JSON',
    '.sql' => 'SQL',
    '.md' => 'Markdown',
    _ => ext.isNotEmpty ? ext.replaceFirst('.', '').toUpperCase() : 'TEXT',
  };
}
