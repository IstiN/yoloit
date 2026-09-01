import 'package:json_annotation/json_annotation.dart';

part 'yoloitd_models.g.dart';

@JsonSerializable()
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
    'icon': metadata['icon'],
    'active': active,
  };

  Map<String, dynamic> toJson() => _$RemoteBoardToJson(this);

  factory RemoteBoard.fromJson(Map<String, dynamic> json) =>
      _$RemoteBoardFromJson(json);
}

@JsonSerializable()
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
  @JsonKey(defaultValue: 'board.note.markdown')
  final String type;
  @JsonKey(defaultValue: 'Panel')
  final String title;
  final RemotePanelBounds bounds;
  final Map<String, dynamic> state;
  final Map<String, dynamic> params;
  final int? color;
  @JsonKey(defaultValue: 0)
  final int zIndex;
  @JsonKey(defaultValue: false)
  final bool hidden;
  @JsonKey(defaultValue: false)
  final bool locked;
  @JsonKey(defaultValue: false)
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

  Map<String, dynamic> toJson() => _$RemotePanelToJson(this);

  factory RemotePanel.fromJson(Map<String, dynamic> json) =>
      _$RemotePanelFromJson(json);
}

@JsonSerializable()
class RemotePanelBounds {
  const RemotePanelBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @JsonKey(defaultValue: 120.0)
  final double x;
  @JsonKey(defaultValue: 120.0)
  final double y;
  @JsonKey(defaultValue: 360.0)
  final double width;
  @JsonKey(defaultValue: 240.0)
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

  Map<String, dynamic> toJson() => _$RemotePanelBoundsToJson(this);

  factory RemotePanelBounds.fromJson(Map<String, dynamic> json) =>
      _$RemotePanelBoundsFromJson(json);
}

@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$RemoteHistoryEventToJson(this);

  factory RemoteHistoryEvent.fromJson(
    Map<String, dynamic> json, {
    String defaultActorId = 'remote',
  }) {
    final mutable = Map<String, dynamic>.from(json);
    mutable['actorId'] ??= defaultActorId;
    return _$RemoteHistoryEventFromJson(mutable);
  }
}

const Object _unset = Object();
