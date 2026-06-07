// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Workspace _$WorkspaceFromJson(Map<String, dynamic> json) => Workspace(
  id: json['id'] as String,
  name: json['name'] as String,
  paths: (json['paths'] as List<dynamic>).map((e) => e as String).toList(),
  gitBranch: json['gitBranch'] as String?,
  addedLines: (json['addedLines'] as num?)?.toInt() ?? 0,
  removedLines: (json['removedLines'] as num?)?.toInt() ?? 0,
  isActive: json['isActive'] as bool? ?? false,
  color: const ColorNullableJsonConverter().fromJson(
    (json['color'] as num?)?.toInt(),
  ),
  enabledSkills:
      (json['enabledSkills'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$WorkspaceToJson(Workspace instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'paths': instance.paths,
  'gitBranch': instance.gitBranch,
  'addedLines': instance.addedLines,
  'removedLines': instance.removedLines,
  'isActive': instance.isActive,
  'color': const ColorNullableJsonConverter().toJson(instance.color),
  'enabledSkills': instance.enabledSkills,
};
