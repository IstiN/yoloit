import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
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
  final nodeById = <String, MindMapNodeData>{for (final node in state.nodes) node.id: node};
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
      .where((node) => node is! WorkspaceNodeData && !reachable.contains(node.id))
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
  final nodeContent = state.nodeContent.isNotEmpty
      ? state.nodeContent
      : {
          for (final node in state.nodes) node.id: _snapshotContentFromNode(node),
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
  final hidden = ((payload['hidden'] as List?) ?? const [])
      .map((entry) => entry.toString())
      .toSet();
  final hiddenTypes = ((payload['hiddenTypes'] as List?) ?? const [])
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
    if (_collapsed) {
      return _SidebarToggle(
        onTap: () => setState(() => _collapsed = false),
      );
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
            color: const Color(0xEE0F1218),
            border: Border.all(color: const Color(0xFF1E2330)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 18),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_tree,
                      size: 14,
                      color: Color(0xFF7C6BFF),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Show / Hide',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8E8FF),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (widget.onHideAll != null)
                      InkWell(
                        onTap: widget.onHideAll,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(
                            'Hide all',
                            style: TextStyle(fontSize: 9, color: Color(0xFFFF6B6B)),
                          ),
                        ),
                      ),
                    if (widget.data.hiddenCount > 0 && widget.onShowAll != null)
                      InkWell(
                        onTap: widget.onShowAll,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(
                            'Show all',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF7C6BFF),
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () => setState(() => _collapsed = true),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.chevron_left,
                          size: 14,
                          color: Color(0xFF6B7898),
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
              const Divider(height: 1, color: Color(0xFF1E2330)),
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
                      const Padding(
                        padding: EdgeInsets.fromLTRB(10, 8, 8, 2),
                        child: Text(
                          'OTHER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A5680),
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
            onDrag: (dx) => setState(() {
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
      List<String> _allDescendantIds(ShowHideSidebarNode n) {
        final ids = <String>[n.id];
        for (final c in n.children) ids.addAll(_allDescendantIds(c));
        return ids;
      }

      final VoidCallback toggleHide = isWorkspace
          ? () => widget.onToggleGroup(_allDescendantIds(node))
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
          onToggleExpand: hasChildren
              ? () => setState(() {
                  expanded
                      ? _expandedIds.remove(node.id)
                      : _expandedIds.add(node.id);
                })
              : null,
          onFocus: widget.onFocusNode != null
              ? () => widget.onFocusNode!(node.id)
              : null,
          onRemoveFolder: widget.onRemoveFolder,
          onHideDescendants: hasChildren && widget.onHideDescendants != null
              ? () => widget.onHideDescendants!(descendantIds())
              : null,
          onShowDescendants: hasChildren && widget.onShowDescendants != null
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
    WorkspaceNodeData data => (
      type: 'workspace',
      label: data.workspace.name,
    ),
    AgentNodeData data => (
      type: 'agent',
      label: data.session.displayName,
    ),
    RepoNodeData data => (
      type: 'repo',
      label: data.repoName,
    ),
    BranchNodeData data => (
      type: 'branch',
      label: data.branch,
    ),
    FilesNodeData data => (
      type: 'files',
      label: p.basename(data.repoPath),
    ),
    FileTreeNodeData data => (
      type: 'tree',
      label: data.repoName ?? 'Tree',
    ),
    DiffNodeData data => (
      type: 'diff',
      label: data.repoName ?? 'Diff',
    ),
    EditorNodeData data => (
      type: 'editor',
      label: p.basename(data.filePath),
    ),
    FilePanelNodeData data => (
      type: 'panel',
      label: p.basename(data.filePath),
    ),
    FileDiffPanelNodeData data => (
      type: 'filediff',
      label: p.basename(data.filePath),
    ),
    RunNodeData data => (
      type: 'run',
      label: data.session.config.name,
    ),
    SessionNodeData data => (
      type: 'session',
      label: data.session.displayName,
    ),
    MindMapPluginNodeData _ => (
      type: 'plugin',
      label: node.id,
    ),
  };
}

Map<String, dynamic> _snapshotContentFromNode(MindMapNodeData node) {
  return switch (node) {
    WorkspaceNodeData data => {
      'type': 'workspace',
      'name': data.workspace.name,
      'path': data.workspace.path,
    },
    AgentNodeData data => {
      'type': 'agent',
      'name': data.session.displayName,
      'status': data.isRunning ? 'live' : 'idle',
    },
    RepoNodeData data => {
      'type': 'repo',
      'name': data.repoName,
      'path': data.repoPath,
      'branch': data.branch,
    },
    BranchNodeData data => {
      'type': 'branch',
      'name': data.branch,
      'branch': data.branch,
    },
    FilesNodeData data => {
      'type': 'files',
      'repoPath': data.repoPath,
    },
    FileTreeNodeData data => {
      'type': 'tree',
      'repoName': data.repoName,
      'repoPath': data.repoPath,
    },
    DiffNodeData data => {
      'type': 'diff',
      'repoName': data.repoName,
      'repoPath': data.repoPath,
    },
    EditorNodeData data => {
      'type': 'editor',
      'filePath': data.filePath,
    },
    FilePanelNodeData data => {
      'type': 'panel',
      'filePath': data.filePath,
    },
    FileDiffPanelNodeData data => {
      'type': 'filediff',
      'filePath': data.filePath,
      'repoPath': data.repoPath,
    },
    RunNodeData data => {
      'type': 'run',
      'name': data.session.config.name,
    },
    SessionNodeData data => {
      'type': 'session',
      'name': data.session.displayName,
    },
    MindMapPluginNodeData data => {
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
    'tree' => content['repoName'] as String? ??
        _basename(content['repoPath'] as String?) ??
        'Tree',
    'diff' => content['repoName'] as String? ??
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

  static const _typeColors = <String, Color>{
    'workspace': Color(0xFF7C6BFF),
    'agent': Color(0xFF34D399),
    'session': Color(0xFF6B7898),
    'repo': Color(0xFF9AA3BF),
    'branch': Color(0xFF60A5FA),
    'run': Color(0xFFFF6B6B),
    'files': Color(0xFFFFAA33),
    'tree': Color(0xFF34D399),
    'diff': Color(0xFF7C6BFF),
    'editor': Color(0xFFFFCC44),
    'plugin': Color(0xFF9AA3BF),
  };

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[node.type] ?? Icons.circle;
    final color = _typeColors[node.type] ?? const Color(0xFF64748B);
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
                    color: node.hidden
                        ? const Color(0xFF4A5680)
                        : const Color(0xFF7C6BFF),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.folder_copy_outlined,
                size: 13,
                color: node.hidden ? const Color(0xFF4A5680) : const Color(0xFF7C6BFF),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: node.hidden
                        ? const Color(0xFF4A5680)
                        : const Color(0xFFE8E8FF),
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 13,
                color: const Color(0xFF6B7898),
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
                color: const Color(0xFF2A3040),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleHide,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    node.hidden ? Icons.visibility_off : Icons.visibility,
                    size: 11,
                    color: node.hidden
                        ? const Color(0xFF4A5680)
                        : const Color(0x997C6BFF),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 11,
                color: node.hidden ? const Color(0xFF3D475E) : color,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  node.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: node.hidden
                        ? const Color(0xFF4A5680)
                        : const Color(0xFFB0B8D0),
                  ),
                ),
              ),
              if (hasChildren) ...[
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 11,
                  color: const Color(0xFF6B7898),
                ),
              ],
              if (node.type == 'diff')
                BlocBuilder<ReviewCubit, ReviewState>(
                  builder: (context, state) {
                    final count = state is ReviewLoaded
                        ? state.changedFiles.length
                        : 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0x337C6BFF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xFF9B8FFF),
                            fontWeight: FontWeight.w600),
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
        onSecondaryTapDown: (details) => _showAgentMenu(context, details.globalPosition),
        child: row,
      );
    }
    // For workspace nodes, right-click shows context menu (copy path + delete).
    if (isWorkspace) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            _showWorkspaceMenu(context, details.globalPosition),
        child: row,
      );
    }
    // For other nodes: right-click shows hide/show children + remove folder.
    final hasDescendantActions = onHideDescendants != null || onShowDescendants != null;
    final isRepoFolder = node.type == 'repo' &&
        onRemoveFolder != null &&
        node.id.startsWith('repo:') &&
        !node.id.startsWith('repo:orphan:');
    if (hasDescendantActions || isRepoFolder) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) =>
            _showNodeMenu(context, details.globalPosition, isRepoFolder),
        child: row,
      );
    }
    return row;
  }

  void _showNodeMenu(BuildContext context, Offset position, bool isRepoFolder) {
    final items = <PopupMenuEntry<String>>[];

    if (onHideDescendants != null) {
      items.add(PopupMenuItem<String>(
        value: 'hide_children',
        height: 32,
        child: Row(
          children: const [
            Icon(Icons.visibility_off_outlined, size: 13, color: Color(0xFF9AA3BF)),
            SizedBox(width: 8),
            Text('Hide all below', style: TextStyle(fontSize: 12, color: Color(0xFF9AA3BF))),
          ],
        ),
      ));
    }
    if (onShowDescendants != null) {
      items.add(PopupMenuItem<String>(
        value: 'show_children',
        height: 32,
        child: Row(
          children: const [
            Icon(Icons.visibility_outlined, size: 13, color: Color(0xFF9AA3BF)),
            SizedBox(width: 8),
            Text('Show all below', style: TextStyle(fontSize: 12, color: Color(0xFF9AA3BF))),
          ],
        ),
      ));
    }

    if (isRepoFolder) {
      if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 8));
      items.add(PopupMenuItem<String>(
        value: 'remove_folder',
        height: 32,
        child: Row(
          children: const [
            Icon(Icons.folder_off_outlined, size: 13, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Remove Folder', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
          ],
        ),
      ));
    }

    if (items.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF1A1E2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF2A3040)),
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
          onRemoveFolder!(rest.substring(0, colonIdx), rest.substring(colonIdx + 1));
        }
      }
    });
  }

  Future<void> _showWorkspaceMenu(BuildContext context, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      color: const Color(0xFF1A1E2A),
      items: [
        if (node.path != null && node.path!.isNotEmpty)
          PopupMenuItem<String>(
            value: 'copy_path',
            height: 32,
            child: Row(
              children: const [
                Icon(Icons.copy_outlined, size: 14, color: Color(0xFFB0B0D0)),
                SizedBox(width: 8),
                Text('Copy path', style: TextStyle(fontSize: 12, color: Color(0xFFB0B0D0))),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.delete_outline, size: 14, color: Color(0xFFFF6B6B)),
              SizedBox(width: 8),
              Text('Delete workspace', style: TextStyle(fontSize: 12, color: Color(0xFFFF6B6B))),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy_path') {
      await Clipboard.setData(ClipboardData(text: node.path!));
    } else if (selected == 'delete') {
      // node.id = 'ws:{workspaceId}'
      final workspaceId = node.id.startsWith('ws:')
          ? node.id.substring(3)
          : node.id;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1E2A),
          title: Text(
            'Delete "${node.label}"?',
            style: const TextStyle(fontSize: 14, color: Color(0xFFE8E8FF)),
          ),
          content: const Text(
            'This will remove the workspace. Sessions and files will not be affected.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9AA3BF)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF7C6BFF))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Color(0xFFFF6B6B))),
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
    final sessionId = node.id.startsWith('agent:') ? node.id.substring(6) : node.id;
    final terminalCubit = context.read<TerminalCubit>();
    final mindMapCubit = context.read<MindMapCubit>();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      color: const Color(0xFF1A1E2A),
      items: [
        PopupMenuItem<String>(
          value: 'rename',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.drive_file_rename_outline, size: 14, color: Color(0xFFB0B0D0)),
              SizedBox(width: 8),
              Text('Rename Session', style: TextStyle(fontSize: 12, color: Color(0xFFB0B0D0))),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.delete_outline, size: 14, color: Color(0xFFFF6B6B)),
              SizedBox(width: 8),
              Text('Delete Session', style: TextStyle(fontSize: 12, color: Color(0xFFFF6B6B))),
            ],
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
    final sessions = state is TerminalLoaded ? state.allSessions : <AgentSession>[];
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    final controller = TextEditingController(text: session?.customName ?? session?.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Rename Session', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Session name...',
            hintStyle: const TextStyle(color: Color(0xFF6B7280)),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF2D3748))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF7C6BFF))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rename', style: TextStyle(color: Color(0xFF7C6BFF), fontWeight: FontWeight.w600)),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Close Session', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        content: const Text(
          'Would you like to pause the session (keep it running in the background) or kill it permanently?',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'pause'),
            child: const Text('Pause', style: TextStyle(color: Color(0xFF7C6BFF), fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'kill'),
            child: const Text('Kill Forever', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
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
              color: _hovered
                  ? const Color(0xFF7C6BFF)
                  : const Color(0x40FFFFFF),
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
    return Tooltip(
      message: 'Show sidebar',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xEE0F1218),
            border: Border.all(color: const Color(0xFF1E2330)),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: const Icon(
            Icons.chevron_right,
            size: 16,
            color: Color(0xFF7C6BFF),
          ),
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
            color: _hovered ? const Color(0xFF2A1E66) : const Color(0xFF1A1E2A),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF7C6BFF)
                  : const Color(0xFF2A3040),
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
                color: _hovered
                    ? const Color(0xFFC084FC)
                    : const Color(0xFF9AA3BF),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _hovered
                      ? const Color(0xFFE8E8FF)
                      : const Color(0xFF9AA3BF),
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
    return Container(
      color: const Color(0xFF0D1018),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.search, size: 12, color: Color(0xFF4A5680)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 11, color: Color(0xFFD0D8F0)),
              cursorColor: const Color(0xFF7C6BFF),
              cursorWidth: 1.5,
              decoration: const InputDecoration(
                hintText: 'Quick filter…',
                hintStyle: TextStyle(fontSize: 11, color: Color(0xFF3A4460)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, val, __) => val.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: controller.clear,
                    child: const Icon(Icons.close, size: 12, color: Color(0xFF4A5680)),
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
    (type: 'agent',  label: 'Sessions', icon: Icons.terminal),
    (type: 'branch', label: 'Branches', icon: Icons.alt_route),
    (type: 'run',    label: 'Runs',     icon: Icons.play_circle_outline),
    (type: 'files',  label: 'Files',    icon: Icons.folder_open_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1018),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: _chips.map((c) {
          final hidden = hiddenTypes.contains(c.type);
          return GestureDetector(
            onTap: () => onToggle(c.type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: hidden ? const Color(0xFF1A1E2A) : const Color(0xFF1E1840),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hidden ? const Color(0xFF2A3040) : const Color(0xFF5C4FCC),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon, size: 10,
                    color: hidden ? const Color(0xFF4A5680) : const Color(0xFF9B8FFF)),
                  const SizedBox(width: 3),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 9,
                      color: hidden ? const Color(0xFF4A5680) : const Color(0xFFB0A8FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hidden) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.visibility_off, size: 8, color: Color(0xFF4A5680)),
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
