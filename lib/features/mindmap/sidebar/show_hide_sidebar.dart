import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';

class ShowHideSidebarNode extends Equatable {
  const ShowHideSidebarNode({
    required this.id,
    required this.type,
    required this.label,
    required this.hidden,
    this.children = const [],
  });

  final String id;
  final String type;
  final String label;
  final bool hidden;
  final List<ShowHideSidebarNode> children;

  @override
  List<Object?> get props => [id, type, label, hidden, children];
}

class ShowHideSidebarData extends Equatable {
  const ShowHideSidebarData({
    this.workspaces = const [],
    this.orphans = const [],
    this.hiddenCount = 0,
  });

  final List<ShowHideSidebarNode> workspaces;
  final List<ShowHideSidebarNode> orphans;
  final int hiddenCount;

  @override
  List<Object?> get props => [workspaces, orphans, hiddenCount];
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
  );
}

class MindMapShowHideSidebar extends StatefulWidget {
  const MindMapShowHideSidebar({
    super.key,
    required this.data,
    required this.onToggleHide,
    this.onFocusNode,
    this.onShowAll,
    this.onCreateWorkspace,
    this.onRemoveFolder,
    this.hiddenTypes = const {},
    this.onToggleType,
    this.onHideDescendants,
    this.onShowDescendants,
  });

  final ShowHideSidebarData data;
  final void Function(String nodeId) onToggleHide;
  final void Function(String nodeId)? onFocusNode;
  final VoidCallback? onShowAll;
  final VoidCallback? onCreateWorkspace;
  /// Called when the user removes a workspace folder via context menu.
  /// Parameters: workspaceId, folderPath.
  final void Function(String workspaceId, String folderPath)? onRemoveFolder;
  /// Currently hidden types (used to style toggle chips).
  final Set<String> hiddenTypes;
  /// Called with the type tag when the user clicks a type-filter chip.
  final void Function(String typeTag)? onToggleType;
  /// Hides all nodes in [ids] (descendants of a row).
  final void Function(Set<String> ids)? onHideDescendants;
  /// Shows all nodes in [ids] (descendants of a row).
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
                    if (widget.data.hiddenCount > 0 && widget.onShowAll != null)
                      InkWell(
                        onTap: widget.onShowAll,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
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
              const Divider(height: 1, color: Color(0xFF1E2330)),
              // ── Type-filter chips ────────────────────────────────────────
              _TypeFilterRow(
                hiddenTypes: widget.hiddenTypes,
                onToggle: widget.onToggleType,
              ),
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
      final expanded = _expandedIds.contains(node.id);
      final descendantIds = hasChildren ? _collectDescendantIds(node) : const <String>{};
      widgets.add(
        _SidebarTreeRow(
          node: node,
          depth: depth,
          isWorkspace: isWorkspace,
          expanded: expanded,
          onToggleHide: () => widget.onToggleHide(node.id),
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
              ? () => widget.onHideDescendants!(descendantIds)
              : null,
          onShowDescendants: hasChildren && widget.onShowDescendants != null
              ? () => widget.onShowDescendants!(descendantIds)
              : null,
        ),
      );
      if (hasChildren && expanded) {
        widgets.addAll(_buildNodes(node.children, depth: depth + 1));
      }
    }
    return widgets;
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
  return ShowHideSidebarNode(
    id: node.id,
    type: meta.type,
    label: meta.label,
    hidden: hidden.contains(node.id) || hiddenTypes.contains(meta.type),
    children: children,
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

/// Collects all descendant node IDs from a [ShowHideSidebarNode] recursively.
Set<String> _collectDescendantIds(ShowHideSidebarNode node) {
  final ids = <String>{};
  for (final child in node.children) {
    ids.add(child.id);
    ids.addAll(_collectDescendantIds(child));
  }
  return ids;
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

    // Parse workspace ID and folder path from repo node IDs like 'repo:{wsId}:{path}'.
    // Nodes with ID 'repo:orphan:...' are not workspace context folders.
    ({String wsId, String folderPath})? repoFolderInfo;
    if (node.type == 'repo' &&
        onRemoveFolder != null &&
        node.id.startsWith('repo:') &&
        !node.id.startsWith('repo:orphan:')) {
      final rest = node.id.substring('repo:'.length);
      final colonIdx = rest.indexOf(':');
      if (colonIdx > 0) {
        repoFolderInfo = (
          wsId: rest.substring(0, colonIdx),
          folderPath: rest.substring(colonIdx + 1),
        );
      }
    }

    void showContextMenu(TapUpDetails details) {
      final hasDescendantActions = onHideDescendants != null || onShowDescendants != null;
      if (!hasDescendantActions && repoFolderInfo == null) return;

      final items = <PopupMenuEntry<String>>[];

      if (hasDescendantActions) {
        if (onHideDescendants != null) {
          items.add(PopupMenuItem<String>(
            value: 'hide_children',
            height: 32,
            child: Row(
              children: const [
                Icon(Icons.visibility_off_outlined, size: 13, color: Color(0xFF9AA3BF)),
                SizedBox(width: 8),
                Text(
                  'Hide all below',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA3BF)),
                ),
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
                Text(
                  'Show all below',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA3BF)),
                ),
              ],
            ),
          ));
        }
      }

      if (repoFolderInfo != null) {
        if (items.isNotEmpty) {
          items.add(const PopupMenuDivider(height: 8));
        }
        items.add(PopupMenuItem<String>(
          value: 'remove',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.folder_off_outlined, size: 13, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text(
                'Remove Folder',
                style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ));
      }

      if (items.isEmpty) return;

      final info = repoFolderInfo;
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy,
        ),
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
        } else if (value == 'remove' && info != null) {
          onRemoveFolder!(info.wsId, info.folderPath);
        }
      });
    }

    if (isWorkspace) {
      final workspaceRow = InkWell(
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
      final hasContext = onHideDescendants != null || onShowDescendants != null;
      if (hasContext) {
        return GestureDetector(
          onSecondaryTapUp: showContextMenu,
          child: workspaceRow,
        );
      }
      return workspaceRow;
    }

    final indent = 10.0 + depth * 14.0;
    final row = InkWell(
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
          ],
        ),
      ),
    );

    final needsContextMenu = repoFolderInfo != null ||
        onHideDescendants != null ||
        onShowDescendants != null;
    if (needsContextMenu) {
      return GestureDetector(
        onSecondaryTapUp: showContextMenu,
        child: row,
      );
    }
    return row;
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

class _TypeFilterRow extends StatelessWidget {
  const _TypeFilterRow({required this.hiddenTypes, this.onToggle});

  final Set<String> hiddenTypes;
  final void Function(String typeTag)? onToggle;

  static const _chips = [
    (tag: 'agent',   label: 'Sessions', icon: Icons.terminal),
    (tag: 'branch',  label: 'Branches', icon: Icons.alt_route),
    (tag: 'run',     label: 'Runs',     icon: Icons.play_circle_outline),
    (tag: 'files',   label: 'Files',    icon: Icons.insert_drive_file_outlined),
    (tag: 'tree',    label: 'Tree',     icon: Icons.account_tree_outlined),
    (tag: 'diff',    label: 'Diff',     icon: Icons.compare_arrows_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final chip in _chips)
            _TypeChip(
              label: chip.label,
              icon: chip.icon,
              hidden: hiddenTypes.contains(chip.tag),
              onTap: onToggle != null ? () => onToggle!(chip.tag) : null,
            ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatefulWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.hidden,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  State<_TypeChip> createState() => _TypeChipState();
}

class _TypeChipState extends State<_TypeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = !widget.hidden;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? (_hovered ? const Color(0xFF2A2060) : const Color(0xFF1E1A40))
                : (_hovered ? const Color(0xFF1A1E2A) : const Color(0xFF12141C)),
            border: Border.all(
              color: active
                  ? const Color(0xFF7C6BFF)
                  : const Color(0xFF2A3040),
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 10,
                color: active
                    ? const Color(0xFFC084FC)
                    : const Color(0xFF4A5680),
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? const Color(0xFFE8E8FF)
                      : const Color(0xFF4A5680),
                ),
              ),
            ],
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
