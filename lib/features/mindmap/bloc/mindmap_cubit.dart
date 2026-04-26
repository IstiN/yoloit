import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/mindmap_layout_engine.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';

class MindMapCubit extends Cubit<MindMapState> {
  MindMapCubit() : super(const MindMapState());

  static const _kPositions   = 'mindmap.positions';
  static const _kLocked      = 'mindmap.locked';
  static const _kSizes       = 'mindmap.sizes';
  static const _kHidden      = 'mindmap.hidden';
  static const _kHiddenTypes = 'mindmap.hiddenTypes';
  static const _kSavedViews  = 'mindmap.saved_views';

  final _engine = MindMapLayoutEngine();

  // ── Load persisted positions ──────────────────────────────────────────────

  Future<void> loadPersistedPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final posJson        = prefs.getString(_kPositions);
    final lockedRaw      = prefs.getStringList(_kLocked);
    final sizesJson      = prefs.getString(_kSizes);
    final hiddenRaw      = prefs.getStringList(_kHidden);
    final hiddenTypesRaw = prefs.getStringList(_kHiddenTypes);
    final savedViewsJson = prefs.getString(_kSavedViews);

    Map<String, Offset> positions = {};
    Set<String> locked = {};
    Set<String> hidden = {};
    Set<String> hiddenTypes = {};
    Map<String, Size> sizes = {};
    Map<String, MindMapViewSnapshot> savedViews = {};

    if (posJson != null) {
      final map = jsonDecode(posJson) as Map<String, dynamic>;
      map.forEach((k, v) {
        final list = (v as List).cast<double>();
        positions[k] = Offset(list[0], list[1]);
      });
    }
    if (lockedRaw != null) locked = lockedRaw.toSet();
    // Filter out stale agent-node hides — agent cards always reappear when
    // their session is live.  This cleans up any pre-fix persisted values too.
    if (hiddenRaw != null) {
      hidden = hiddenRaw.where((id) => !id.startsWith('agent:')).toSet();
    }
    if (hiddenTypesRaw != null) hiddenTypes = hiddenTypesRaw.toSet();
    if (sizesJson != null) {
      final map = jsonDecode(sizesJson) as Map<String, dynamic>;
      map.forEach((k, v) {
        final list = (v as List).cast<double>();
        sizes[k] = Size(list[0], list[1]);
      });
    }
    if (savedViewsJson != null) {
      final map = jsonDecode(savedViewsJson) as Map<String, dynamic>;
      map.forEach((k, v) {
        savedViews[k] = MindMapViewSnapshot.fromJson(v as Map<String, dynamic>);
      });
    }

    emit(state.copyWith(
      positions:   positions,
      locked:      locked,
      sizes:       sizes,
      hidden:      hidden,
      hiddenTypes: hiddenTypes,
      savedViews:  savedViews,
    ));

    // If all positions are at (0,0) (corrupted save from first-open bug), clear them.
    if (positions.isNotEmpty &&
        positions.values.every((o) => o.dx < 10 && o.dy < 10)) {
      emit(state.copyWith(positions: {}, locked: {}, sizes: {}));
      await prefs.remove(_kPositions);
      await prefs.remove(_kLocked);
      await prefs.remove(_kSizes);
    }
  }

  // ── Named views ───────────────────────────────────────────────────────────

  Future<void> saveView(String name) async {
    final snapshot = MindMapViewSnapshot(
      name:        name,
      positions:   Map.from(state.positions),
      sizes:       Map.from(state.sizes),
      locked:      Set.from(state.locked),
      hidden:      Set.from(state.hidden),
      hiddenTypes: Set.from(state.hiddenTypes),
    );
    final newViews = Map<String, MindMapViewSnapshot>.from(state.savedViews)
      ..[name] = snapshot;
    emit(state.copyWith(savedViews: newViews, activeViewName: name));
    await _saveSavedViews(newViews);
  }

  void loadView(String name) {
    final snap = state.savedViews[name];
    if (snap == null) return;
    final newPositions = Map<String, Offset>.from(snap.positions);
    // Re-run layout for any nodes that aren't in the snapshot.
    final computed = _engine.compute(
      nodes:    state.nodes,
      existing: newPositions,
      sizes:    snap.sizes,
      locked:   snap.locked,
    );
    emit(state.copyWith(
      positions:      computed,
      sizes:          Map.from(snap.sizes),
      locked:         Set.from(snap.locked),
      hidden:         Set.from(snap.hidden),
      hiddenTypes:    Set.from(snap.hiddenTypes),
      activeViewName: name,
    ));
    _savePositions(computed);
    _saveLocked(snap.locked);
    _saveSizes(snap.sizes);
    _saveHidden(snap.hidden);
    _saveHiddenTypes(snap.hiddenTypes);
  }

  Future<void> deleteView(String name) async {
    final newViews = Map<String, MindMapViewSnapshot>.from(state.savedViews)
      ..remove(name);
    final newActive = state.activeViewName == name ? null : state.activeViewName;
    emit(state.copyWith(
      savedViews:           newViews,
      activeViewName:       newActive,
      clearActiveViewName: newActive == null,
    ));
    await _saveSavedViews(newViews);
  }

  // ── Update nodes (called when blocs emit) ─────────────────────────────────

  void updateNodes(
    List<MindMapNodeData> nodes,
    List<MindMapConnection> connections,
  ) {
    // Preserve EditorNodeData panels that were manually opened via
    // openFileAsPanel() — they are NOT produced by the graph builder
    // (which only emits 'editor:active') and must survive rebuild cycles.
    // Also preserve FilePanelNodeData nodes (the new standalone panel type).
    final panelEditors = state.nodes
        .where((n) =>
            (n is EditorNodeData && n.id != 'editor:active' ||
             n is FilePanelNodeData ||
             n is FileDiffPanelNodeData) &&
            !nodes.any((m) => m.id == n.id))
        .toList();
    if (panelEditors.isNotEmpty) {
      debugPrint('[MindMapCubit] updateNodes: preserving ${panelEditors.length} panel nodes: ${panelEditors.map((n) => n.id).toList()}');
    }
    final panelConns = state.connections
        .where((c) => panelEditors.any((n) => n.id == c.fromId || n.id == c.toId))
        .toList();

    // Collect all file paths that already have a FilePanelNodeData —
    // both from preserved panels and from the incoming graph nodes.
    final panelFilePaths = {
      ...panelEditors.whereType<FilePanelNodeData>().map((n) => n.filePath),
      ...nodes.whereType<FilePanelNodeData>().map((n) => n.filePath),
    };

    // Suppress ANY EditorNodeData (including old persisted 'panel:...' nodes)
    // when there's already a FilePanelNodeData for the same file — this
    // prevents the duplicate Code/Preview toolbar from appearing.
    final filteredNodes = nodes.where((n) {
      if (n is EditorNodeData) {
        return !panelFilePaths.contains(n.filePath);
      }
      return true;
    }).toList();

    // Also remove stale EditorNodeData panels from preserved list.
    final filteredPanelEditors = panelEditors.where((n) {
      if (n is EditorNodeData) {
        return !panelFilePaths.contains(n.filePath);
      }
      return true;
    }).toList();

    final mergedNodes = [...filteredNodes, ...filteredPanelEditors];
    final mergedConns = [...connections, ...panelConns];

    final newPositions = _engine.compute(
      nodes:       mergedNodes,
      existing:    state.positions,
      sizes:       state.sizes,
      locked:      state.locked,
      connections: mergedConns,
    );

    // Auto-reveal only BRAND NEW live sessions (not previously in the graph).
    // This avoids un-hiding sessions that were explicitly hidden in a saved view.
    final prevAgentIds = state.nodes.whereType<AgentNodeData>().map((a) => a.id).toSet();
    final newLiveAgentIds = nodes.whereType<AgentNodeData>()
        .where((a) => a.session.status == AgentStatus.live && !prevAgentIds.contains(a.id))
        .map((a) => a.id)
        .toSet();
    final newHidden = newLiveAgentIds.isEmpty
        ? state.hidden
        : ({...state.hidden}..removeAll(newLiveAgentIds));

    emit(state.copyWith(
      nodes:       mergedNodes,
      connections: mergedConns,
      positions:   newPositions,
      hidden:      newHidden,
    ));
    _savePositions(newPositions);
    if (newHidden != state.hidden) _saveHidden(newHidden);
  }

  // ── Drag ──────────────────────────────────────────────────────────────────

  void moveNode(String id, Offset delta) {
    final current = state.positions[id] ?? Offset.zero;
    final newPos  = Offset(
      current.dx + delta.dx,
      current.dy + delta.dy,
    );
    final newPositions = Map<String, Offset>.from(state.positions)..[id] = newPos;
    final newLocked    = {...state.locked, id};
    emit(state.copyWith(positions: newPositions, locked: newLocked));
    _savePositions(newPositions);
    _saveLocked(newLocked);
  }

  // ── Resize ────────────────────────────────────────────────────────────────

  void resizeNode(String id, Offset delta, Size minSize) {
    final current = state.sizes[id] ?? const Size(200, 200);
    final newSize = Size(
      (current.width  + delta.dx).clamp(minSize.width,  double.infinity),
      (current.height + delta.dy).clamp(minSize.height, double.infinity),
    );
    final newSizes = Map<String, Size>.from(state.sizes)..[id] = newSize;
    emit(state.copyWith(sizes: newSizes));
    _saveSizes(newSizes);
  }

  /// Resize from the left edge: adjusts both position.x and size.width.
  void resizeFromLeft(String id, double dx, Size minSize) {
    final currentPos  = state.positions[id]  ?? Offset.zero;
    final currentSize = state.sizes[id]      ?? const Size(200, 200);

    final newWidth    = (currentSize.width - dx).clamp(minSize.width, double.infinity);
    final clampedDx   = currentSize.width - newWidth;
    final newPos      = Offset(currentPos.dx + clampedDx, currentPos.dy);
    final newSize     = Size(newWidth, currentSize.height);

    final newPositions = Map<String, Offset>.from(state.positions)..[id] = newPos;
    final newSizes     = Map<String, Size>.from(state.sizes)..[id]       = newSize;
    final newLocked    = {...state.locked, id};

    emit(state.copyWith(positions: newPositions, sizes: newSizes, locked: newLocked));
    _savePositions(newPositions);
    _saveSizes(newSizes);
    _saveLocked(newLocked);
  }

  /// Returns the current rendered size of [id], falling back to default.
  Size sizeOf(String id, Size fallback) => state.sizes[id] ?? fallback;

  // ── Hide / show ───────────────────────────────────────────────────────────

  void hideNode(String id) {
    final newHidden = {...state.hidden, id};
    emit(state.copyWith(hidden: newHidden));
    _saveHidden(newHidden);
  }

  /// Hides multiple nodes at once (e.g. all children of a parent).
  void hideNodes(Set<String> ids) {
    if (ids.isEmpty) return;
    final newHidden = {...state.hidden, ...ids};
    emit(state.copyWith(hidden: newHidden));
    _saveHidden(newHidden);
  }

  /// Shows (un-hides) multiple nodes at once.
  void showNodes(Set<String> ids) {
    if (ids.isEmpty) return;
    final newHidden = {...state.hidden}..removeAll(ids);
    emit(state.copyWith(hidden: newHidden));
    _saveHidden(newHidden);
  }

  /// Permanently remove a node from the canvas (positions, sizes, connections too).
  /// Use this for manually-opened panels (file editors, diffs) so they don't
  /// reappear when "Show all" is triggered.
  void removeNode(String id) {
    final newNodes = state.nodes.where((n) => n.id != id).toList();
    final newPositions = {...state.positions}..remove(id);
    final newSizes = {...state.sizes}..remove(id);
    final newConns = state.connections
        .where((c) => c.fromId != id && c.toId != id)
        .toList();
    final newHidden = {...state.hidden}..remove(id);
    emit(state.copyWith(
      nodes: newNodes,
      positions: newPositions,
      sizes: newSizes,
      connections: newConns,
      hidden: newHidden,
    ));
    _saveHidden(newHidden);
  }

  /// Hide every node currently on the canvas.
  void hideAll() {
    final allIds = state.nodes.map((n) => n.id).toSet();
    emit(state.copyWith(hidden: allIds, hiddenTypes: {}));
    _saveHidden(allIds);
    _saveHiddenTypes({});
  }

  /// Toggle visibility for a group of IDs together (e.g. a workspace + children).
  /// If any of the IDs is currently visible, hides all; otherwise shows all.
  void toggleGroupVisibility(List<String> ids) {
    final anyVisible = ids.any((id) => !state.hidden.contains(id));
    final newHidden = {...state.hidden};
    if (anyVisible) {
      newHidden.addAll(ids);
    } else {
      newHidden.removeAll(ids);
    }
    emit(state.copyWith(hidden: newHidden));
    _saveHidden(newHidden);
  }

  void showAllNodes() {
    emit(state.copyWith(hidden: {}, hiddenTypes: {}));
    _saveHidden({});
    _saveHiddenTypes({});
  }

  /// Toggle whether all nodes with a given [typeTag] are hidden.
  void toggleType(String typeTag) {
    final newTypes = {...state.hiddenTypes};
    if (newTypes.contains(typeTag)) {
      newTypes.remove(typeTag);
    } else {
      newTypes.add(typeTag);
    }
    emit(state.copyWith(hiddenTypes: newTypes));
    _saveHiddenTypes(newTypes);
  }

  /// Unhide a single node id (remove from hidden set).
  void showNode(String id) {
    if (!state.hidden.contains(id)) return;
    final newHidden = {...state.hidden}..remove(id);
    emit(state.copyWith(hidden: newHidden));
    _saveHidden(newHidden);
  }

  // ── Reset layout ──────────────────────────────────────────────────────────

  void resetLayout() {
    final newPositions = _engine.compute(
      nodes:       state.nodes,
      existing:    {},
      sizes:       state.sizes,
      locked:      {},
      connections: state.connections,
    );
    emit(state.copyWith(positions: newPositions, locked: {}, hidden: {}, hiddenTypes: {}));
    _savePositions(newPositions);
    _saveLocked({});
    _saveHidden({});
    _saveHiddenTypes({});
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _savePositions(Map<String, Offset> pos) async {
    final prefs = await SharedPreferences.getInstance();
    final map = pos.map((k, v) => MapEntry(k, [v.dx, v.dy]));
    await prefs.setString(_kPositions, jsonEncode(map));
  }

  Future<void> _saveSizes(Map<String, Size> sizes) async {
    final prefs = await SharedPreferences.getInstance();
    final map = sizes.map((k, v) => MapEntry(k, [v.width, v.height]));
    await prefs.setString(_kSizes, jsonEncode(map));
  }

  Future<void> _saveLocked(Set<String> locked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kLocked, locked.toList());
  }

  Future<void> _saveHidden(Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    // Don't persist individual agent card hides — sessions always reappear on
    // restart and their cards should reappear too.  Type-level hides ('agent'
    // in hiddenTypes) still persist so the user's deliberate "hide all
    // terminals" choice is remembered.
    final toSave = hidden.where((id) => !id.startsWith('agent:')).toList();
    await prefs.setStringList(_kHidden, toSave);
  }

  Future<void> _saveHiddenTypes(Set<String> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHiddenTypes, types.toList());
  }

  Future<void> _saveSavedViews(Map<String, MindMapViewSnapshot> views) async {
    final prefs = await SharedPreferences.getInstance();
    final map = views.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_kSavedViews, jsonEncode(map));
  }

  // ── Open file as panel node ───────────────────────────────────────────────

  void openFileAsPanel({
    required String id,
    required String filePath,
  }) {
    if (state.nodes.any((n) => n.id == id)) {
      // Already on canvas — just unhide it.
      final newHidden = {...state.hidden}..remove(id);
      emit(state.copyWith(hidden: newHidden));
      _saveHidden(newHidden);
      return;
    }
    final newNode = FilePanelNodeData(id: id, filePath: filePath);

    // Connect from the matching file tree node (if any).
    final treeNode = state.nodes.whereType<FileTreeNodeData>().where(
      (n) => n.repoPath != null && filePath.startsWith(n.repoPath!),
    ).firstOrNull;

    final newNodes = [...state.nodes, newNode];
    final newConnections = treeNode != null
        ? [
            ...state.connections,
            MindMapConnection(
              fromId: treeNode.id,
              toId: id,
              style: ConnectorStyle.dashed,
              color: const Color(0x7060A5FA),
            ),
          ]
        : state.connections;

    final newPositions = _engine.compute(
      nodes: newNodes,
      existing: state.positions,
      sizes: state.sizes,
      locked: state.locked,
      connections: newConnections,
    );
    emit(state.copyWith(
      nodes: newNodes,
      positions: newPositions,
      connections: newConnections,
    ));
    _savePositions(newPositions);
  }

  void openFileDiffAsPanel({
    required String filePath,
    required String repoPath,
  }) {
    final id = 'filediff:${filePath.hashCode}';
    debugPrint('[MindMapCubit] openFileDiffAsPanel id=$id, state.nodes.length=${state.nodes.length}');
    if (state.nodes.any((n) => n.id == id)) {
      debugPrint('[MindMapCubit] node already exists, unhiding');
      final newHidden = {...state.hidden}..remove(id);
      emit(state.copyWith(hidden: newHidden));
      _saveHidden(newHidden);
      return;
    }
    final newNode = FileDiffPanelNodeData(
      id: id,
      filePath: filePath,
      repoPath: repoPath,
    );

    // Connect from the diff node (if any).
    final diffNode = state.nodes.whereType<DiffNodeData>().where(
      (n) => n.repoPath == repoPath,
    ).firstOrNull;
    debugPrint('[MindMapCubit] diffNode found: ${diffNode?.id}');

    final newNodes = [...state.nodes, newNode];
    final newConnections = diffNode != null
        ? [
            ...state.connections,
            MindMapConnection(
              fromId: diffNode.id,
              toId: id,
              style: ConnectorStyle.dashed,
              color: const Color(0x7060A5FA),
            ),
          ]
        : state.connections;

    final newPositions = _engine.compute(
      nodes: newNodes,
      existing: state.positions,
      sizes: state.sizes,
      locked: state.locked,
      connections: newConnections,
    );
    debugPrint('[MindMapCubit] newNodes.length=${newNodes.length}, pos for $id=${newPositions[id]}');
    emit(state.copyWith(
      nodes: newNodes,
      positions: newPositions,
      connections: newConnections,
    ));
    _savePositions(newPositions);
  }

  // ── Remote collaboration helpers ──────────────────────────────────────────

  /// Applies a full state snapshot received from the host.
  /// Does NOT persist — guest state is ephemeral (mirrors host).
  void applyRemoteSnapshot({
    required Map<String, Offset>    positions,
    required Map<String, Size>      sizes,
    required Set<String>            hidden,
    required Set<String>            hiddenTypes,
    List<MindMapConnection>         connections = const [],
    Map<String, Map<String, dynamic>> nodeContent = const {},
    Map<String, MindMapViewSnapshot> savedViews = const {},
    List<MindMapNodeData>           remoteNodes = const [],
    Map<String, int>                nodeColors  = const {},
  }) {
    // Merge remote-only nodes (e.g. FilePanelNodeData created on the host)
    // that don't exist in local state. Existing local nodes are preserved.
    List<MindMapNodeData>? mergedNodes;
    if (remoteNodes.isNotEmpty) {
      final localIds = state.nodes.map((n) => n.id).toSet();
      final newRemote =
          remoteNodes.where((n) => !localIds.contains(n.id)).toList();
      if (newRemote.isNotEmpty) {
        mergedNodes = [...state.nodes, ...newRemote];
      }
    }
    emit(state.copyWith(
      positions:   {...state.positions, ...positions},
      sizes:       {...state.sizes, ...sizes},
      hidden:      hidden,
      hiddenTypes: hiddenTypes,
      connections: connections.isNotEmpty ? connections : null,
      nodeContent: nodeContent.isNotEmpty ? nodeContent : null,
      savedViews:  savedViews.isNotEmpty ? savedViews : null,
      nodes:       mergedNodes,
      nodeColors:  nodeColors.isNotEmpty ? nodeColors : null,
    ));
  }

  /// Applies a single node-moved delta from the host.
  void applyRemoteMove(String nodeId, Offset pos) {
    emit(state.copyWith(positions: {...state.positions, nodeId: pos}));
  }

  /// Applies a single node-resized delta from the host.
  void applyRemoteResize(String nodeId, Size size) {
    emit(state.copyWith(sizes: {...state.sizes, nodeId: size}));
  }

  /// Updates content for a single node (terminal stream, file content, etc.).
  void updateNodeContent(String nodeId, Map<String, dynamic> content) {
    final updated = Map<String, Map<String, dynamic>>.from(state.nodeContent);
    updated[nodeId] = content;
    emit(state.copyWith(nodeContent: updated));
  }
}
