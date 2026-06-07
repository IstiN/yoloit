// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_env_groups_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GlobalEnvGroup _$GlobalEnvGroupFromJson(Map<String, dynamic> json) =>
    GlobalEnvGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      values:
          (json['values'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          {},
    );

Map<String, dynamic> _$GlobalEnvGroupToJson(GlobalEnvGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'values': instance.values,
    };
