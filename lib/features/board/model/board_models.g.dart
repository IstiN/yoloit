// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'board_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BoardPanelBounds _$BoardPanelBoundsFromJson(Map<String, dynamic> json) =>
    BoardPanelBounds(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 320.0,
      height: (json['height'] as num?)?.toDouble() ?? 220.0,
    );

Map<String, dynamic> _$BoardPanelBoundsToJson(BoardPanelBounds instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
    };

BoardPanelInstance _$BoardPanelInstanceFromJson(Map<String, dynamic> json) =>
    BoardPanelInstance(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String? ?? 'Panel',
      bounds: BoardPanelBounds.fromJson(json['bounds'] as Map<String, dynamic>),
      color: const ColorNullableJsonConverter().fromJson(
        (json['color'] as num?)?.toInt(),
      ),
      params: json['params'] as Map<String, dynamic>? ?? const {},
      state: json['state'] as Map<String, dynamic>? ?? const {},
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      hidden: json['hidden'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
    );

Map<String, dynamic> _$BoardPanelInstanceToJson(BoardPanelInstance instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'title': instance.title,
      'bounds': instance.bounds.toJson(),
      'color': const ColorNullableJsonConverter().toJson(instance.color),
      'params': instance.params,
      'state': instance.state,
      'zIndex': instance.zIndex,
      'hidden': instance.hidden,
      'locked': instance.locked,
      'pinned': instance.pinned,
    };

BoardPanelLink _$BoardPanelLinkFromJson(Map<String, dynamic> json) =>
    BoardPanelLink(
      id: json['id'] as String,
      fromPanelId: json['fromPanelId'] as String,
      toPanelId: json['toPanelId'] as String,
      style:
          $enumDecodeNullable(_$BoardLinkStyleEnumMap, json['style']) ??
          BoardLinkStyle.arrow,
      behavior:
          $enumDecodeNullable(_$BoardLinkBehaviorEnumMap, json['behavior']) ??
          BoardLinkBehavior.fixed,
      color:
          json['color'] == null
              ? Colors.lightBlueAccent
              : const ColorJsonConverter().fromJson(
                (json['color'] as num).toInt(),
              ),
      geometry:
          $enumDecodeNullable(_$BoardLinkGeometryEnumMap, json['geometry']) ??
          BoardLinkGeometry.bezier,
    );

Map<String, dynamic> _$BoardPanelLinkToJson(BoardPanelLink instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fromPanelId': instance.fromPanelId,
      'toPanelId': instance.toPanelId,
      'style': _$BoardLinkStyleEnumMap[instance.style]!,
      'behavior': _$BoardLinkBehaviorEnumMap[instance.behavior]!,
      'color': const ColorJsonConverter().toJson(instance.color),
      'geometry': _$BoardLinkGeometryEnumMap[instance.geometry]!,
    };

const _$BoardLinkStyleEnumMap = {
  BoardLinkStyle.line: 'line',
  BoardLinkStyle.arrow: 'arrow',
};

const _$BoardLinkBehaviorEnumMap = {
  BoardLinkBehavior.fixed: 'fixed',
  BoardLinkBehavior.dynamic: 'dynamic',
};

const _$BoardLinkGeometryEnumMap = {
  BoardLinkGeometry.bezier: 'bezier',
  BoardLinkGeometry.straight: 'straight',
  BoardLinkGeometry.elbow: 'elbow',
};
