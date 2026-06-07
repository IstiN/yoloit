// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mindmap_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MindMapViewSnapshot _$MindMapViewSnapshotFromJson(Map<String, dynamic> json) =>
    MindMapViewSnapshot(
      name: json['name'] as String,
      positions: const OffsetMapJsonConverter().fromJson(
        json['positions'] as Map<String, List<double>>,
      ),
      sizes: const SizeMapJsonConverter().fromJson(
        json['sizes'] as Map<String, List<double>>,
      ),
      locked: const StringSetJsonConverter().fromJson(
        json['locked'] as List<String>,
      ),
      hidden: const StringSetJsonConverter().fromJson(
        json['hidden'] as List<String>,
      ),
      hiddenTypes: const StringSetJsonConverter().fromJson(
        json['hiddenTypes'] as List<String>,
      ),
    );

Map<String, dynamic> _$MindMapViewSnapshotToJson(
  MindMapViewSnapshot instance,
) => <String, dynamic>{
  'name': instance.name,
  'positions': const OffsetMapJsonConverter().toJson(instance.positions),
  'sizes': const SizeMapJsonConverter().toJson(instance.sizes),
  'locked': const StringSetJsonConverter().toJson(instance.locked),
  'hidden': const StringSetJsonConverter().toJson(instance.hidden),
  'hiddenTypes': const StringSetJsonConverter().toJson(instance.hiddenTypes),
};
