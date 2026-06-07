// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'yoloitd_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RemoteBoard _$RemoteBoardFromJson(Map<String, dynamic> json) => RemoteBoard(
  id: json['id'] as String,
  name: json['name'] as String,
  viewport:
      json['viewport'] as Map<String, dynamic>? ??
      const <String, dynamic>{
        'scale': 1.0,
        'translation': <String, dynamic>{'dx': 0.0, 'dy': 0.0},
      },
  panels:
      (json['panels'] as List<dynamic>?)
          ?.map((e) => RemotePanel.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RemotePanel>[],
  links:
      (json['links'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const <Map<String, dynamic>>[],
  drawings:
      (json['drawings'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const <Map<String, dynamic>>[],
  metadata:
      json['metadata'] as Map<String, dynamic>? ?? const <String, dynamic>{},
);

Map<String, dynamic> _$RemoteBoardToJson(RemoteBoard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'viewport': instance.viewport,
      'panels': instance.panels,
      'links': instance.links,
      'drawings': instance.drawings,
      'metadata': instance.metadata,
    };

RemotePanel _$RemotePanelFromJson(Map<String, dynamic> json) => RemotePanel(
  id: json['id'] as String,
  type: json['type'] as String? ?? 'board.note.markdown',
  title: json['title'] as String? ?? 'Panel',
  bounds: RemotePanelBounds.fromJson(json['bounds'] as Map<String, dynamic>),
  state: json['state'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  params: json['params'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  color: (json['color'] as num?)?.toInt(),
  zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
  hidden: json['hidden'] as bool? ?? false,
  locked: json['locked'] as bool? ?? false,
  pinned: json['pinned'] as bool? ?? false,
);

Map<String, dynamic> _$RemotePanelToJson(RemotePanel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'title': instance.title,
      'bounds': instance.bounds,
      'state': instance.state,
      'params': instance.params,
      'color': instance.color,
      'zIndex': instance.zIndex,
      'hidden': instance.hidden,
      'locked': instance.locked,
      'pinned': instance.pinned,
    };

RemotePanelBounds _$RemotePanelBoundsFromJson(Map<String, dynamic> json) =>
    RemotePanelBounds(
      x: (json['x'] as num?)?.toDouble() ?? 120.0,
      y: (json['y'] as num?)?.toDouble() ?? 120.0,
      width: (json['width'] as num?)?.toDouble() ?? 360.0,
      height: (json['height'] as num?)?.toDouble() ?? 240.0,
    );

Map<String, dynamic> _$RemotePanelBoundsToJson(RemotePanelBounds instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
    };

RemoteHistoryEvent _$RemoteHistoryEventFromJson(Map<String, dynamic> json) =>
    RemoteHistoryEvent(
      opId: json['opId'] as String,
      boardId: json['boardId'] as String,
      type: json['type'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      actorId: json['actorId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      revision: (json['revision'] as num).toInt(),
      before: json['before'] as Map<String, dynamic>?,
      after: json['after'] as Map<String, dynamic>?,
      patch:
          json['patch'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      restoresOpId: json['restoresOpId'] as String?,
    );

Map<String, dynamic> _$RemoteHistoryEventToJson(RemoteHistoryEvent instance) =>
    <String, dynamic>{
      'opId': instance.opId,
      'boardId': instance.boardId,
      'type': instance.type,
      'entityType': instance.entityType,
      'entityId': instance.entityId,
      'actorId': instance.actorId,
      'timestamp': instance.timestamp.toIso8601String(),
      'revision': instance.revision,
      'before': instance.before,
      'after': instance.after,
      'patch': instance.patch,
      'restoresOpId': instance.restoresOpId,
    };
