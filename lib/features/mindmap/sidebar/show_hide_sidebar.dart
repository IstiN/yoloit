import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

class ShowHideSidebarNode extends Equatable {
  const ShowHideSidebarNode({
    required this.id,
    required this.type,
    required this.label,
    required this.hidden,
    this.children = const [],
    this.path,
  });

  final String id;
  final String type;
  final String label;
  final bool hidden;
  final List<ShowHideSidebarNode> children;

  /// Optional filesystem path (populated for workspace nodes).
  final String? path;

  @override
  List<Object?> get props => [id, type, label, hidden, children, path];
}

class ShowHideSidebarData extends Equatable {
  const ShowHideSidebarData({
    this.workspaces = const [],
    this.orphans = const [],
    this.hiddenCount = 0,
    this.hiddenTypes = const {},
  });

  final List<ShowHideSidebarNode> workspaces;
  final List<ShowHideSidebarNode> orphans;
  final int hiddenCount;
  final Set<String> hiddenTypes;

  @override
  List<Object?> get props => [workspaces, orphans, hiddenCount, hiddenTypes];
}

ShowHideSidebarData buildShowHideSidebarDataFromMindMapState(
  MindMapState state,
) {
  final nodeById = <String, MindMapNodeData>{
    for (final node in state.nodes) node.id: node,
  };
  final childMap = _buildChildMap(
    state.connections
        .map((c) => (fromId: c.fromId, toId: c.toId))
        .toList(growable: false),
  );
  final workspaceIds = state.nodes
      .whereType<WorkspaceNodeData>()
      .map((workspace) => workspace.id)
      .toList(growable: false);

  final reachable = <String>{};
  for (final workspaceId in workspaceIds) {
    _collectReachableIds(workspaceId, childMap, reachable);
  }

  final workspaces = workspaceIds
      .map(
        (workspaceId) => _buildDesktopNode(
          workspaceId,
          nodeById: nodeById,
          childMap: childMap,
          hidden: state.hidden,
          hiddenTypes: state.hiddenTypes,
          visited: <String>{},
        ),
      )
      .whereType<ShowHideSidebarNode>()
      .toList(growable: false);

  final orphans = state.nodes
      .where(
        (node) => node is! WorkspaceNodeData && !reachable.contains(node.id),
      )
      .map(
        (node) => _buildDesktopNode(
          node.id,
          nodeById: nodeById,
          childMap: const {},
          hidden: state.hidden,
          hiddenTypes: state.hiddenTypes,
          visited: <String>{},
        ),
      )
      .whereType<ShowHideSidebarNode>()
      .toList(growable: false);

  return ShowHideSidebarData(
    workspaces: workspaces,
    orphans: orphans,
    hiddenCount: state.hidden.length + state.hiddenTypes.length,
    hiddenTypes: state.hiddenTypes,
  );
}

Map<String, dynamic> buildShowHideSidebarSnapshotPayloadFromMindMapState(
  MindMapState state,
) {
  final nodeContent =
      state.nodeContent.isNotEmpty
          ? state.nodeContent
          : {
            for (final node in state.nodes)
              node.id: _snapshotContentFromNode(node),
          };
  return {
    'positions': state.positions.map(
      (id, offset) => MapEntry(id, [offset.dx, offset.dy]),
    ),
    'hidden': state.hidden.toList(),
    'hiddenTypes': state.hiddenTypes.toList(),
    'connections': state.connections
        .map((connection) => {'from': connection.fromId, 'to': connection.toId})
        .toList(growable: false),
    'nodeContent': nodeContent,
  };
}

ShowHideSidebarData buildShowHideSidebarDataFromSnapshotPayload(
  Map<String, dynamic> payload,
) {
  final positions = (payload['positions'] as Map<String, dynamic>? ?? const {})
      .keys
      .cast<String>()
      .toList(growable: false);
  final hidden =
      ((payload['hidden'] as List?) ?? const [])
          .map((entry) => entry.toString())
          .toSet();
  final hiddenTypes =
      ((payload['hiddenTypes'] as List?) ?? const [])
          .map((entry) => entry.toString())
          .toSet();
  final connections = ((payload['connections'] as List?) ?? const [])
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
  final nodeContentRaw = Map<String, dynamic>.from(
    payload['nodeContent'] as Map? ?? const {},
  );
  final nodeContent = {
    for (final entry in nodeContentRaw.entries)
      entry.key: Map<String, dynamic>.from(entry.value as Map),
  };

  final childMap = _buildChildMap(
    connections
        .map(
          (entry) => (
            fromId: entry['from'] as String? ?? '',
            toId: entry['to'] as String? ?? '',
          ),
        )
        .where((entry) => entry.fromId.isNotEmpty && entry.toId.isNotEmpty)
        .toList(growable: false),
  );

  final workspaceIds = positions
      .where((id) => _snapshotType(id, nodeContent[id]) == 'workspace')
      .toList(growable: false);

  final reachable = <String>{};
  for (final workspaceId in workspaceIds) {
    _collectReachableIds(workspaceId, childMap, reachable);
  }

  final workspaces = workspaceIds
      .map(
        (workspaceId) => _buildSnapshotNode(
          workspaceId,
          nodeContent: nodeContent,
          childMap: childMap,
          hidden: hidden,
          hiddenTypes: hiddenTypes,
          visited: <String>{},
        ),
      )
      .whereType<ShowHideSidebarNode>()
      .toList(growable: false);

  final orphans = positions
      .where((id) => !workspaceIds.contains(id) && !reachable.contains(id))
      .map(
        (id) => _buildSnapshotNode(
          id,
          nodeContent: nodeContent,
          childMap: const {},
          hidden: hidden,
          hiddenTypes: hiddenTypes,
          visited: <String>{},
        ),
      )
      .whereType<ShowHideSidebarNode>()
      .toList(growable: false);

  return ShowHideSidebarData(
    workspaces: workspaces,
    orphans: orphans,
    hiddenCount: hidden.length + hiddenTypes.length,
    hiddenTypes: hiddenTypes,
  );
}

class MindMapShowHideSidebar extends StatefulWidget {
  const MindMapShowHideSidebar({
    super.key,
    required this.data,
    required this.onToggleHide,
    required this.onToggleGroup,
    this.onFocusNode,
    this.onShowAll,
    this.onHideAll,
    this.onToggleType,
    this.onCreateWorkspace,
    this.onRemoveFolder,
    this.onHideDescendants,
    this.onShowDescendants,
  });

  final ShowHideSidebarData data;
  final void Function(String nodeId) onToggleHide;

  /// Toggle a group of node IDs together (workspace + its children).
  final void Function(List<String> ids) onToggleGroup;
  final void Function(String nodeId)? onFocusNode;
  final VoidCallback? onShowAll;
  final VoidCallback? onHideAll;
  final void Function(String typeTag)? onToggleType;
  final VoidCallback? onCreateWorkspace;

  /// Called when the user removes a workspace folder via right-click.
  final void Function(String workspaceId, String folderPath)? onRemoveFolder;

  /// Hides all nodes in [ids] (all children of a row).
  final void Function(Set<String> ids)? onHideDescendants;

  /// Shows all nodes in [ids] (all children of a row).
  final void Function(Set<String> ids)? onShowDescendants;

  @override
  State<MindMapShowHideSidebar> createState() => _MindMapShowHideSidebarState();
}

class _MindMapShowHideSidebarState extends State<MindMapShowHideSidebar> {
  bool _collapsed = false;
  double _width = 220;

  static const _minWidth = 160.0;
  static const _maxWidth = 480.0;

  final _expandedIds = <String>{};
  final _autoExpandedWorkspaceIds = <String>{};

  final _filterCtrl = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(() {
      setState(() => _filterQuery = _filterCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_collapsed) {
      return _SidebarToggle(onTap: () => setState(() => _collapsed = false));
    }

    for (final workspace in widget.data.workspaces) {
      if (_autoExpandedWorkspaceIds.add(workspace.id)) {
        _expandedIds.add(workspace.id);
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _width,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: colors.background.withValues(alpha: 0.5),
                blurRadius: 18,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    Icon(Icons.account_tree, size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Show / Hide',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (widget.onHideAll != null)
                      InkWell(
                        onTap: widget.onHideAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            'Hide all',
                            style: TextStyle(
                              fontSize: 9,
                              color: colors.accentRed,
                            ),
                          ),
                        ),
                      ),
                    if (widget.data.hiddenCount > 0 && widget.onShowAll != null)
                      InkWell(
                        onTap: widget.onShowAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            'Show all',
                            style: TextStyle(
                              fontSize: 9,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () => setState(() => _collapsed = true),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.chevron_left,
                          size: 14,
                          color:
                              context.appColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Type filter chips ───────────────────────────────────────
              if (widget.onToggleType != null)
                _TypeFilterBar(
                  hiddenTypes: widget.data.hiddenTypes,
                  onToggle: widget.onToggleType!,
                ),
              // ── Quick search filter ─────────────────────────────────────
              _QuickFilterBar(controller: _filterCtrl),
              Divider(height: 1, color: context.appColors.divider),
              if (widget.onCreateWorkspace != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: _SidebarAction(
                    icon: Icons.create_new_folder_outlined,
                    label: '+ Workspace',
                    onTap: widget.onCreateWorkspace!,
                  ),
                ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    ..._buildNodes(widget.data.workspaces, depth: 0),
                    if (widget.data.orphans.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 2),
                        child: Text(
                          'OTHER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      ..._buildNodes(widget.data.orphans, depth: 1),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: -4,
          top: 0,
          bottom: 0,
          width: 8,
          child: _SidebarResizeHandle(
            onDrag:
                (dx) => setState(() {
                  _width = (_width + dx).clamp(_minWidth, _maxWidth);
                }),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildNodes(
    List<ShowHideSidebarNode> nodes, {
    required int depth,
  }) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final isWorkspace = depth == 0 && node.type == 'workspace';
      final hasChildren = node.children.isNotEmpty;

      // When a filter is active, only show nodes whose label (or any descendant) matches.
      // Auto-expand workspaces that contain matches.
      final bool filterActive = _filterQuery.isNotEmpty;
      if (filterActive && !_nodeMatchesFilter(node, _filterQuery)) continue;
      if (filterActive && isWorkspace) {
        // Force-expand workspaces so matching children are visible.
        _expandedIds.add(node.id);
      }

      final expanded = _expandedIds.contains(node.id);

      // For workspace rows, toggling hides/shows workspace + all descendant IDs together.
      List<String> allDescendantIds(ShowHideSidebarNode n) {
        final ids = <String>[n.id];
        for (final c in n.children) {
          ids.addAll(allDescendantIds(c));
        }
        return ids;
      }

      final VoidCallback toggleHide =
          isWorkspace
              ? () => widget.onToggleGroup(allDescendantIds(node))
              : () => widget.onToggleHide(node.id);

      // Collect descendant IDs as a Set for hide/show-all-children callbacks.
      Set<String> descendantIds() {
        final ids = <String>{};
        for (final c in node.children) {
          ids.add(c.id);
          void collect(ShowHideSidebarNode n) {
            for (final ch in n.children) {
              ids.add(ch.id);
              collect(ch);
            }
          }

          collect(c);
        }
        return ids;
      }

      widgets.add(
        _SidebarTreeRow(
          node: node,
          depth: depth,
          isWorkspace: isWorkspace,
          expanded: expanded,
          onToggleHide: toggleHide,
          onToggleExpand:
              hasChildren
                  ? () => setState(() {
                    expanded
                        ? _expandedIds.remove(node.id)
                        : _expandedIds.add(node.id);
                  })
                  : null,
          onFocus:
              widget.onFocusNode != null
                  ? () => widget.onFocusNode!(node.id)
                  : null,
          onRemoveFolder: widget.onRemoveFolder,
          onHideDescendants:
              hasChildren && widget.onHideDescendants != null
                  ? () => widget.onHideDescendants!(descendantIds())
                  : null,
          onShowDescendants:
              hasChildren && widget.onShowDescendants != null
                  ? () => widget.onShowDescendants!(descendantIds())
                  : null,
        ),
      );
      if (hasChildren && expanded) {
        widgets.addAll(_buildNodes(node.children, depth: depth + 1));
      }
    }
    return widgets;
  }

  /// Returns true if the node's label or any descendant label matches [query].
  bool _nodeMatchesFilter(ShowHideSidebarNode node, String query) {
    if (node.label.toLowerCase().contains(query)) return true;
    for (final child in node.children) {
      if (_nodeMatchesFilter(child, query)) return true;
    }
    return false;
  }
}

Map<String, List<String>> _buildChildMap(
  List<({String fromId, String toId})> connections,
) {
  final childMap = <String, List<String>>{};
  for (final connection in connections) {
    (childMap[connection.fromId] ??= []).add(connection.toId);
  }
  return childMap;
}

ShowHideSidebarNode? _buildDesktopNode(
  String id, {
  required Map<String, MindMapNodeData> nodeById,
  required Map<String, List<String>> childMap,
  required Set<String> hidden,
  required Set<String> hiddenTypes,
  required Set<String> visited,
}) {
  final node = nodeById[id];
  if (node == null || !visited.add(id)) return null;

  final children = <ShowHideSidebarNode>[];
  for (final childId in childMap[id] ?? const <String>[]) {
    final child = _buildDesktopNode(
      childId,
      nodeById: nodeById,
      childMap: childMap,
      hidden: hidden,
      hiddenTypes: hiddenTypes,
      visited: {...visited},
    );
    if (child != null) children.add(child);
  }

  final meta = _desktopMeta(node);
  final workspacePath = node is WorkspaceNodeData ? node.workspace.path : null;
  return ShowHideSidebarNode(
    id: node.id,
    type: meta.type,
    label: meta.label,
    hidden: hidden.contains(node.id) || hiddenTypes.contains(meta.type),
    children: children,
    path: workspacePath,
  );
}

ShowHideSidebarNode? _buildSnapshotNode(
  String id, {
  required Map<String, Map<String, dynamic>> nodeContent,
  required Map<String, List<String>> childMap,
  required Set<String> hidden,
  required Set<String> hiddenTypes,
  required Set<String> visited,
}) {
  if (!visited.add(id)) return null;
  final content = nodeContent[id] ?? const <String, dynamic>{};
  final type = _snapshotType(id, content);

  final children = <ShowHideSidebarNode>[];
  for (final childId in childMap[id] ?? const <String>[]) {
    final child = _buildSnapshotNode(
      childId,
      nodeContent: nodeContent,
      childMap: childMap,
      hidden: hidden,
      hiddenTypes: hiddenTypes,
      visited: {...visited},
    );
    if (child != null) children.add(child);
  }

  return ShowHideSidebarNode(
    id: id,
    type: type,
    label: _snapshotLabel(id, content, type),
    hidden: hidden.contains(id) || hiddenTypes.contains(type),
    children: children,
    path: type == 'workspace' ? content['path'] as String? : null,
  );
}

void _collectReachableIds(
  String id,
  Map<String, List<String>> childMap,
  Set<String> out,
) {
  for (final child in childMap[id] ?? const <String>[]) {
    if (out.add(child)) {
      _collectReachableIds(child, childMap, out);
    }
  }
}

({String type, String label}) _desktopMeta(MindMapNodeData node) {
  return switch (node) {
    final WorkspaceNodeData data => (type: 'workspace', label: data.workspace.name),
    final AgentNodeData data => (type: 'agent', label: data.session.displayName),
    final RepoNodeData data => (type: 'repo', label: data.repoName),
    final BranchNodeData data => (type: 'branch', label: data.branch),
    final FilesNodeData data => (type: 'files', label: p.basename(data.repoPath)),
    final FileTreeNodeData data => (type: 'tree', label: data.repoName ?? 'Tree'),
    final DiffNodeData data => (type: 'diff', label: data.repoName ?? 'Diff'),
    final EditorNodeData data => (type: 'editor', label: p.basename(data.filePath)),
    final FilePanelNodeData data => (type: 'panel', label: p.basename(data.filePath)),
    final FileDiffPanelNodeData data => (
      type: 'filediff',
      label: p.basename(data.filePath),
    ),
    final RunNodeData data => (type: 'run', label: data.session.config.name),
    final SessionNodeData data => (type: 'session', label: data.session.displayName),
    MindMapPluginNodeData _ => (type: 'plugin', label: node.id),
  };
}

Map<String, dynamic> _snapshotContentFromNode(MindMapNodeData node) {
  return switch (node) {
    final WorkspaceNodeData data => {
      'type': 'workspace',
      'name': data.workspace.name,
      'path': data.workspace.path,
    },
    final AgentNodeData data => {
      'type': 'agent',
      'name': data.session.displayName,
      'status': data.isRunning ? 'live' : 'idle',
    },
    final RepoNodeData data => {
      'type': 'repo',
      'name': data.repoName,
      'path': data.repoPath,
      'branch': data.branch,
    },
    final BranchNodeData data => {
      'type': 'branch',
      'name': data.branch,
      'branch': data.branch,
    },
    final FilesNodeData data => {'type': 'files', 'repoPath': data.repoPath},
    final FileTreeNodeData data => {
      'type': 'tree',
      'repoName': data.repoName,
      'repoPath': data.repoPath,
    },
    final DiffNodeData data => {
      'type': 'diff',
      'repoName': data.repoName,
      'repoPath': data.repoPath,
    },
    final EditorNodeData data => {'type': 'editor', 'filePath': data.filePath},
    final FilePanelNodeData data => {'type': 'panel', 'filePath': data.filePath},
    final FileDiffPanelNodeData data => {
      'type': 'filediff',
      'filePath': data.filePath,
      'repoPath': data.repoPath,
    },
    final RunNodeData data => {'type': 'run', 'name': data.session.config.name},
    final SessionNodeData data => {
      'type': 'session',
      'name': data.session.displayName,
    },
    final MindMapPluginNodeData data => {
      'type': 'plugin',
      'pluginId': data.pluginId,
      'name': data.id,
    },
  };
}

String _snapshotType(String id, Map<String, dynamic>? content) {
  final explicitType = content?['type'] as String?;
  if (explicitType != null && explicitType.isNotEmpty) return explicitType;
  final separator = id.indexOf(':');
  if (separator <= 0) return id;
  final prefix = id.substring(0, separator);
  return prefix == 'ws' ? 'workspace' : prefix;
}

String _snapshotLabel(String id, Map<String, dynamic> content, String type) {
  final explicitName = content['name'] as String?;
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;

  return switch (type) {
    'workspace' => _basename(content['path'] as String?) ?? 'Workspace',
    'repo' => _basename(content['path'] as String?) ?? 'Repository',
    'branch' => content['branch'] as String? ?? 'Branch',
    'files' => _basename(content['repoPath'] as String?) ?? 'Files',
    'tree' =>
      content['repoName'] as String? ??
          _basename(content['repoPath'] as String?) ??
          'Tree',
    'diff' =>
      content['repoName'] as String? ??
          _basename(content['repoPath'] as String?) ??
          'Diff',
    'editor' => _basename(content['filePath'] as String?) ?? 'Editor',
    'run' => 'Run',
    'agent' => 'Terminal',
    'session' => 'Session',
    'plugin' => content['pluginId'] as String? ?? 'Plugin',
    _ => type,
  };
}

String? _basename(String? value) {
  if (value == null || value.isEmpty) return null;
  return p.basename(value);
}

class _SidebarTreeRow extends StatelessWidget {
  const _SidebarTreeRow({
    required this.node,
    required this.depth,
    required this.isWorkspace,
    required this.expanded,
    required this.onToggleHide,
    this.onToggleExpand,
    this.onFocus,
    this.onRemoveFolder,
    this.onHideDescendants,
    this.onShowDescendants,
  });

  final ShowHideSidebarNode node;
  final int depth;
  final bool isWorkspace;
  final bool expanded;
  final VoidCallback onToggleHide;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onFocus;
  final void Function(String workspaceId, String folderPath)? onRemoveFolder;

  /// Hides all descendants of this node.
  final VoidCallback? onHideDescendants;

  /// Shows all descendants of this node.
  final VoidCallback? onShowDescendants;

  static const _typeIcons = <String, IconData>{
    'workspace': Icons.folder_copy_outlined,
    'agent': Icons.terminal,
    'session': Icons.terminal,
    'repo': Icons.source,
    'branch': Icons.alt_route,
    'run': Icons.play_circle_outline,
    'files': Icons.insert_drive_file_outlined,
    'tree': Icons.account_tree_outlined,
    'diff': Icons.compare_arrows_rounded,
    'editor': Icons.code,
    'plugin': Icons.extension_outlined,
  };

  ({Color color, bool isMuted}) _typeColor(AppColorScheme colors) =>
      switch (node.type) {
        'workspace' => (color: colors.primary, isMuted: false),
        'agent' => (color: colors.accentGreen, isMuted: false),
        'session' => (color: colors.textMuted, isMuted: true),
        'repo' => (color: colors.textSecondary, isMuted: false),
        'branch' => (color: colors.accentBlue, isMuted: false),
        'run' => (color: colors.accentRed, isMuted: false),
        'files' => (color: colors.accentOrange, isMuted: false),
        'tree' => (color: colors.accentGreen, isMuted: false),
        'diff' => (color: colors.primary, isMuted: false),
        'editor' => (color: colors.accentOrange, isMuted: false),
        'plugin' => (color: colors.textSecondary, isMuted: false),
        _ => (color: colors.textMuted, isMuted: true),
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        context.appColors.textMuted;
    final icon = _typeIcons[node.type] ?? Icons.circle;
    final rawColor = _typeColor(colors);
    final color = rawColor.isMuted ? mutedColor : rawColor.color;
    final hasChildren = node.children.isNotEmpty;
    final isAgent = node.type == 'agent';

    Widget row;

    if (isWorkspace) {
      row = InkWell(
        onTap: onToggleExpand,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggleHide,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    node.hidden ? Icons.visibility_off : Icons.visibility,
                    size: 13,
                    color:
                        node.hidden
                            ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128)
                            : colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.folder_copy_outlined,
                size: 13,
                color:
                    node.hidden
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(128)
                        : colors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        node.hidden
                            ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128)
                            : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 13,
                color: mutedColor,
              ),
            ],
          ),
        ),
      );
    } else {
      final indent = 10.0 + depth * 14.0;
      row = InkWell(
        onTap: hasChildren ? onToggleExpand : onFocus,
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent, 3, 8, 3),
          child: Row(
            children: [
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.only(right: 5),
                color: colors.border,
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleHide,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    node.hidden ? Icons.visibility_off : Icons.visibility,
                    size: 11,
                    color:
                        node.hidden
                            ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128)
                            : colors.primary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 11,
                color:
                    node.hidden
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(76)
                        : color,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  node.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color:
                        node.hidden
                            ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128)
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(153),
                  ),
                ),
              ),
              if (hasChildren) ...[
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 11,
                  color: mutedColor,
                ),
              ],
              if (node.type == 'diff')
                BlocBuilder<ReviewCubit, ReviewState>(
                  builder: (context, state) {
                    final count =
                        state is ReviewLoaded ? state.changedFiles.length : 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 8,
                          color: colors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }

    // For agent nodes, wrap with a right-click context menu to allow deletion.
    if (isAgent) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown:
            (details) => _showAgentMenu(context, details.globalPosition),
        child: row,
      );
    }
    // For workspace nodes, right-click shows context menu (copy path + delete).
    if (isWorkspace) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown:
            (details) => _showWorkspaceMenu(context, details.globalPosition),
        child: row,
      );
    }
    // For other nodes: right-click shows hide/show children + remove folder.
    final hasDescendantActions =
        onHideDescendants != null || onShowDescendants != null;
    final isRepoFolder =
        node.type == 'repo' &&
        onRemoveFolder != null &&
        node.id.startsWith('repo:') &&
        !node.id.startsWith('repo:orphan:');
    if (hasDescendantActions || isRepoFolder) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp:
            (details) =>
                _showNodeMenu(context, details.globalPosition, isRepoFolder),
        child: row,
      );
    }
    return row;
  }

  void _showNodeMenu(BuildContext context, Offset position, bool isRepoFolder) {
    final items = <PopupMenuEntry<String>>[];

    if (onHideDescendants != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'hide_children',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
              const SizedBox(width: 8),
              Text(
                'Hide all below',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (onShowDescendants != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'show_children',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
              const SizedBox(width: 8),
              Text(
                'Show all below',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isRepoFolder) {
      if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 8));
      items.add(
        PopupMenuItem<String>(
          value: 'remove_folder',
          height: 32,
          child: Builder(
            builder: (context) {
              final colors = context.appColors;
              return Row(
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 13,
                    color: colors.accentRed,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remove Folder',
                    style: TextStyle(fontSize: 12, color: colors.accentRed),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    if (items.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: context.appColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: context.appColors.border),
      ),
      items: items,
    ).then((value) {
      if (value == 'hide_children') {
        onHideDescendants?.call();
      } else if (value == 'show_children') {
        onShowDescendants?.call();
      } else if (value == 'remove_folder') {
        final rest = node.id.substring('repo:'.length);
        final colonIdx = rest.indexOf(':');
        if (colonIdx > 0) {
          onRemoveFolder!(
            rest.substring(0, colonIdx),
            rest.substring(colonIdx + 1),
          );
        }
      }
    });
  }

  Future<void> _showWorkspaceMenu(BuildContext context, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: context.appColors.surfaceElevated,
      items: [
        if (node.path != null && node.path!.isNotEmpty)
          PopupMenuItem<String>(
            value: 'copy_path',
            height: 32,
            child: Row(
              children: [
                Icon(
                  Icons.copy_outlined,
                  size: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(153),
                ),
                const SizedBox(width: 8),
                Text(
                  'Copy path',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(153),
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Builder(
            builder: (context) {
              final colors = context.appColors;
              return Row(
                children: [
                  Icon(Icons.delete_outline, size: 14, color: colors.accentRed),
                  const SizedBox(width: 8),
                  Text(
                    'Delete workspace',
                    style: TextStyle(fontSize: 12, color: colors.accentRed),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
    if (selected == 'copy_path') {
      await copyToClipboard(node.path!);
    } else if (selected == 'delete') {
      // node.id = 'ws:{workspaceId}'
      final workspaceId =
          node.id.startsWith('ws:') ? node.id.substring(3) : node.id;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dlgCtx) => AlertDialog(
              backgroundColor: context.appColors.surfaceElevated,
              title: Text(
                'Delete "${node.label}"?',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(dlgCtx).colorScheme.onSurface,
                ),
              ),
              content: Text(
                'This will remove the workspace. Sessions and files will not be affected.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    dlgCtx,
                  ).colorScheme.onSurface.withAlpha(153),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.appColors.primary),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Delete',
                    style: TextStyle(color: context.appColors.accentRed),
                  ),
                ),
              ],
            ),
      );
      if (confirmed == true && context.mounted) {
        await context.read<WorkspaceCubit>().removeWorkspace(workspaceId);
      }
    }
  }

  void _showAgentMenu(BuildContext context, Offset position) {
    // node.id = 'agent:{sessionId}'
    final sessionId =
        node.id.startsWith('agent:') ? node.id.substring(6) : node.id;
    final terminalCubit = context.read<TerminalCubit>();
    final mindMapCubit = context.read<MindMapCubit>();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: context.appColors.surfaceElevated,
      items: [
        PopupMenuItem<String>(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.drive_file_rename_outline,
                size: 14,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
              const SizedBox(width: 8),
              Text(
                'Rename Session',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Builder(
            builder: (context) {
              final colors = context.appColors;
              return Row(
                children: [
                  Icon(Icons.delete_outline, size: 14, color: colors.accentRed),
                  const SizedBox(width: 8),
                  Text(
                    'Delete Session',
                    style: TextStyle(fontSize: 12, color: colors.accentRed),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'rename') {
        await _showRenameDialog(context, sessionId, terminalCubit);
      } else if (value == 'delete') {
        await _showCloseDialog(context, sessionId, terminalCubit, mindMapCubit);
      }
    });
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    String sessionId,
    TerminalCubit terminalCubit,
  ) async {
    final state = terminalCubit.state;
    final sessions =
        state is TerminalLoaded ? state.allSessions : <AgentSession>[];
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    final controller = TextEditingController(
      text: session?.customName ?? session?.displayName ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: context.appColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(
              'Rename Session',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Session name...',
                hintStyle: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurface.withAlpha(128),
                ),
                filled: true,
                fillColor: context.appColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: context.appColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: context.appColors.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: Text(
                  'Rename',
                  style: TextStyle(
                    color: context.appColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      terminalCubit.renameSession(sessionId, result.trim());
    }
  }

  Future<void> _showCloseDialog(
    BuildContext context,
    String sessionId,
    TerminalCubit terminalCubit,
    MindMapCubit mindMapCubit,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: context.appColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(
              'Close Session',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Text(
              'Would you like to pause the session (keep it running in the background) or kill it permanently?',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface.withAlpha(153),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'pause'),
                child: Text(
                  'Pause',
                  style: TextStyle(
                    color: context.appColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'kill'),
                child: Text(
                  'Kill Forever',
                  style: TextStyle(
                    color: context.appColors.accentRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
    if (!context.mounted) return;
    if (result == 'pause') {
      mindMapCubit.hideNode('agent:$sessionId');
    } else if (result == 'kill') {
      terminalCubit.closeSession(sessionId);
    }
  }
}

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => widget.onDrag(details.delta.dx),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _hovered ? 3 : 1,
            height: double.infinity,
            decoration: BoxDecoration(
              color:
                  _hovered
                      ? colors.primary
                      : colors.textPrimary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarToggle extends StatelessWidget {
  const _SidebarToggle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: 'Show sidebar',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 48,
          decoration: BoxDecoration(
            color: context.appColors.surfaceElevated,
            border: Border.all(color: context.appColors.border),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Icon(Icons.chevron_right, size: 16, color: colors.primary),
        ),
      ),
    );
  }
}

class _SidebarAction extends StatefulWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHighlight : colors.surfaceElevated,
            border: Border.all(
              color: _hovered ? colors.primary : colors.border,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color:
                    _hovered
                        ? colors.primaryLight
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(153),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color:
                      _hovered
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick filter search bar ────────────────────────────────────────────────

class _QuickFilterBar extends StatelessWidget {
  const _QuickFilterBar({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 12,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              cursorColor: colors.primary,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: 'Quick filter…',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(102),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder:
                (_, val, __) =>
                    val.text.isEmpty
                        ? const SizedBox.shrink()
                        : GestureDetector(
                          onTap: controller.clear,
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(128),
                          ),
                        ),
          ),
        ],
      ),
    );
  }
}

// ── Type filter chips bar ──────────────────────────────────────────────────

class _TypeFilterBar extends StatelessWidget {
  const _TypeFilterBar({required this.hiddenTypes, required this.onToggle});

  final Set<String> hiddenTypes;
  final void Function(String) onToggle;

  static const _chips = [
    (type: 'agent', label: 'Sessions', icon: Icons.terminal),
    (type: 'branch', label: 'Branches', icon: Icons.alt_route),
    (type: 'run', label: 'Runs', icon: Icons.play_circle_outline),
    (type: 'files', label: 'Files', icon: Icons.folder_open_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children:
            _chips.map((c) {
              final hidden = hiddenTypes.contains(c.type);
              return GestureDetector(
                onTap: () => onToggle(c.type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        hidden
                            ? colors.surfaceElevated
                            : colors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hidden ? colors.border : colors.primary,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.icon,
                        size: 10,
                        color:
                            hidden
                                ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(128)
                                : colors.primaryLight,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        c.label,
                        style: TextStyle(
                          fontSize: 9,
                          color:
                              hidden
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withAlpha(128)
                                  : colors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hidden) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.visibility_off,
                          size: 8,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(128),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
