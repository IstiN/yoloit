class RemoteBoard {
  const RemoteBoard({
    required this.id,
    required this.name,
    this.viewport = const <String, dynamic>{
      'scale': 1.0,
      'translation': <String, dynamic>{'dx': 0.0, 'dy': 0.0},
    },
    this.panels = const <RemotePanel>[],
    this.links = const <Map<String, dynamic>>[],
    this.drawings = const <Map<String, dynamic>>[],
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final Map<String, dynamic> viewport;
  final List<RemotePanel> panels;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> drawings;
  final Map<String, dynamic> metadata;

  int get historyRevision =>
      (metadata['historyRevision'] as num?)?.toInt() ?? 0;

  RemoteBoard copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? viewport,
    List<RemotePanel>? panels,
    List<Map<String, dynamic>>? links,
    List<Map<String, dynamic>>? drawings,
    Map<String, dynamic>? metadata,
  }) {
    return RemoteBoard(
      id: id ?? this.id,
      name: name ?? this.name,
      viewport: viewport ?? this.viewport,
      panels: panels ?? this.panels,
      links: links ?? this.links,
      drawings: drawings ?? this.drawings,
      metadata: metadata ?? this.metadata,
    );
  }

  RemoteBoard withHistoryRevision(int revision) {
    return copyWith(
      metadata: <String, dynamic>{...metadata, 'historyRevision': revision},
    );
  }

  Map<String, dynamic> summary({required bool active}) => <String, dynamic>{
    'id': id,
    'name': name,
    'panelCount': panels.length,
    'linkCount': links.length,
    'defaultFolder': (metadata['defaultFolder'] as String? ?? '').trim(),
    'active': active,
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'viewport': viewport,
    'panels': panels.map((panel) => panel.toJson()).toList(),
    'links': links,
    'drawings': drawings,
    'metadata': metadata,
  };

  factory RemoteBoard.fromJson(Map<String, dynamic> json) {
    return RemoteBoard(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Board',
      viewport: Map<String, dynamic>.from(
        json['viewport'] as Map? ??
            const <String, dynamic>{
              'scale': 1.0,
              'translation': <String, dynamic>{'dx': 0.0, 'dy': 0.0},
            },
      ),
      panels:
          (json['panels'] as List? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map(
                (entry) =>
                    RemotePanel.fromJson(Map<String, dynamic>.from(entry)),
              )
              .toList(),
      links:
          (json['links'] as List? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
      drawings:
          (json['drawings'] as List? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
  }
}

class RemotePanel {
  const RemotePanel({
    required this.id,
    required this.type,
    required this.title,
    required this.bounds,
    this.state = const <String, dynamic>{},
    this.params = const <String, dynamic>{},
    this.color,
    this.zIndex = 0,
    this.hidden = false,
    this.locked = false,
    this.pinned = false,
  });

  final String id;
  final String type;
  final String title;
  final RemotePanelBounds bounds;
  final Map<String, dynamic> state;
  final Map<String, dynamic> params;
  final int? color;
  final int zIndex;
  final bool hidden;
  final bool locked;
  final bool pinned;

  RemotePanel copyWith({
    String? id,
    String? type,
    String? title,
    RemotePanelBounds? bounds,
    Map<String, dynamic>? state,
    Map<String, dynamic>? params,
    Object? color = _unset,
    int? zIndex,
    bool? hidden,
    bool? locked,
    bool? pinned,
  }) {
    return RemotePanel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      bounds: bounds ?? this.bounds,
      state: state ?? this.state,
      params: params ?? this.params,
      color: identical(color, _unset) ? this.color : color as int?,
      zIndex: zIndex ?? this.zIndex,
      hidden: hidden ?? this.hidden,
      locked: locked ?? this.locked,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'title': title,
    'bounds': bounds.toJson(),
    'state': state,
    'params': params,
    if (color != null) 'color': color,
    'zIndex': zIndex,
    'hidden': hidden,
    'locked': locked,
    'pinned': pinned,
  };

  factory RemotePanel.fromJson(Map<String, dynamic> json) {
    return RemotePanel(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'board.note.markdown',
      title: json['title'] as String? ?? 'Panel',
      bounds: RemotePanelBounds.fromJson(
        Map<String, dynamic>.from(json['bounds'] as Map? ?? const {}),
      ),
      state: Map<String, dynamic>.from(json['state'] as Map? ?? const {}),
      params: Map<String, dynamic>.from(json['params'] as Map? ?? const {}),
      color: (json['color'] as num?)?.toInt(),
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      hidden: json['hidden'] == true,
      locked: json['locked'] == true,
      pinned: json['pinned'] == true,
    );
  }
}

class RemotePanelBounds {
  const RemotePanelBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  RemotePanelBounds copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return RemotePanelBounds(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory RemotePanelBounds.fromJson(Map<String, dynamic> json) {
    return RemotePanelBounds(
      x: (json['x'] as num?)?.toDouble() ?? 120.0,
      y: (json['y'] as num?)?.toDouble() ?? 120.0,
      width: (json['width'] as num?)?.toDouble() ?? 360.0,
      height: (json['height'] as num?)?.toDouble() ?? 240.0,
    );
  }
}

class RemoteHistoryEvent {
  const RemoteHistoryEvent({
    required this.opId,
    required this.boardId,
    required this.type,
    required this.entityType,
    required this.entityId,
    required this.actorId,
    required this.timestamp,
    required this.revision,
    this.before,
    this.after,
    this.patch = const <String, dynamic>{},
    this.restoresOpId,
  });

  final String opId;
  final String boardId;
  final String type;
  final String entityType;
  final String entityId;
  final String actorId;
  final DateTime timestamp;
  final int revision;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic> patch;
  final String? restoresOpId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'opId': opId,
    'boardId': boardId,
    'type': type,
    'entityType': entityType,
    'entityId': entityId,
    'actorId': actorId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'revision': revision,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    if (patch.isNotEmpty) 'patch': patch,
    if (restoresOpId != null) 'restoresOpId': restoresOpId,
  };

  factory RemoteHistoryEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? readMap(String key) {
      final value = json[key];
      return value is Map ? Map<String, dynamic>.from(value) : null;
    }

    return RemoteHistoryEvent(
      opId: json['opId'] as String,
      boardId: json['boardId'] as String,
      type: json['type'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      actorId: json['actorId'] as String? ?? 'remote',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      before: readMap('before'),
      after: readMap('after'),
      patch: readMap('patch') ?? const <String, dynamic>{},
      restoresOpId: json['restoresOpId'] as String?,
    );
  }
}

const Object _unset = Object();
