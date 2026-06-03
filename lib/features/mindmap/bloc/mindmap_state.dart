import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';

/// Snapshot of the canvas layout at a point in time.
class MindMapViewSnapshot {
  const MindMapViewSnapshot({
    required this.name,
    required this.positions,
    required this.sizes,
    required this.locked,
    required this.hidden,
    required this.hiddenTypes,
  });
  final String name;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  final Set<String> locked;
  final Set<String> hidden;
  final Set<String> hiddenTypes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'positions': positions.map((k, v) => MapEntry(k, [v.dx, v.dy])),
    'sizes': sizes.map((k, v) => MapEntry(k, [v.width, v.height])),
    'locked': locked.toList(),
    'hidden': hidden.toList(),
    'hiddenTypes': hiddenTypes.toList(),
  };

  factory MindMapViewSnapshot.fromJson(Map<String, dynamic> j) {
    final Map<String, Offset> positions = {};
    final Map<String, Size> sizes = {};
    (j['positions'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final l = (v as List).cast<double>();
      positions[k] = Offset(l[0], l[1]);
    });
    (j['sizes'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final l = (v as List).cast<double>();
      sizes[k] = Size(l[0], l[1]);
    });
    return MindMapViewSnapshot(
      name:        j['name'] as String,
      positions:   positions,
      sizes:       sizes,
      locked:      ((j['locked'] as List?) ?? []).cast<String>().toSet(),
      hidden:      ((j['hidden'] as List?) ?? []).cast<String>().toSet(),
      hiddenTypes: ((j['hiddenTypes'] as List?) ?? []).cast<String>().toSet(),
    );
  }
}

class MindMapState extends Equatable {
  const MindMapState({
    this.positions = const {},
    this.sizes     = const {},
    this.locked    = const {},
    this.hidden    = const {},
    this.hiddenTypes = const {},
    this.nodes     = const [],
    this.connections = const [],
    this.savedViews  = const {},
    this.activeViewName,
    this.nodeContent = const {},
    this.nodeColors  = const {},
  });

  /// Node id → canvas offset (top-left corner).
  final Map<String, Offset> positions;

  /// Node id → current rendered size.
  final Map<String, Size> sizes;

  /// Node ids that have been manually dragged and should not be auto-relayouted.
  final Set<String> locked;

  /// Node ids that the user has hidden via the close button.
  final Set<String> hidden;

  /// Group type tags that are currently hidden via the sidebar.
  final Set<String> hiddenTypes;

  /// All node data (re-built when blocs emit new state).
  final List<MindMapNodeData> nodes;

  /// Connections between nodes.
  final List<MindMapConnection> connections;

  /// Named layout snapshots.
  final Map<String, MindMapViewSnapshot> savedViews;

  /// Currently active view name, null = unsaved / default.
  final String? activeViewName;

  /// Rich content per node received from the host (browser guest only).
  /// Map of nodeId → JSON-serializable content map.
  final Map<String, Map<String, dynamic>> nodeContent;

  /// Per-node custom colours received from the collaboration host.
  /// Key: node id, Value: ARGB colour integer (Color.toARGB32()).
  /// Empty on the host machine; populated on guests when a snapshot is applied.
  final Map<String, int> nodeColors;

  MindMapState copyWith({
    Map<String, Offset>? positions,
    Map<String, Size>?   sizes,
    Set<String>?         locked,
    Set<String>?         hidden,
    Set<String>?         hiddenTypes,
    List<MindMapNodeData>? nodes,
    List<MindMapConnection>? connections,
    Map<String, MindMapViewSnapshot>? savedViews,
    String? activeViewName,
    bool clearActiveViewName = false,
    Map<String, Map<String, dynamic>>? nodeContent,
    Map<String, int>? nodeColors,
  }) {
    return MindMapState(
      positions:      positions      ?? this.positions,
      sizes:          sizes          ?? this.sizes,
      locked:         locked         ?? this.locked,
      hidden:         hidden         ?? this.hidden,
      hiddenTypes:    hiddenTypes    ?? this.hiddenTypes,
      nodes:          nodes          ?? this.nodes,
      connections:    connections    ?? this.connections,
      savedViews:     savedViews     ?? this.savedViews,
      activeViewName: clearActiveViewName ? null : (activeViewName ?? this.activeViewName),
      nodeContent:    nodeContent    ?? this.nodeContent,
      nodeColors:     nodeColors     ?? this.nodeColors,
    );
  }

  @override
  List<Object?> get props => [
    positions, sizes, locked, hidden, hiddenTypes,
    nodes, connections, savedViews, activeViewName, nodeContent, nodeColors,
  ];
}
