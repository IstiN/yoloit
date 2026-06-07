// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skill_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SkillEntry _$SkillEntryFromJson(Map<String, dynamic> json) => SkillEntry(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
  source: json['source'] as String,
  sourceType: $enumDecode(_$SkillSourceTypeEnumMap, json['sourceType']),
  storeId: json['storeId'] as String?,
  installCommand: json['installCommand'] as String?,
  installUrl: json['installUrl'] as String?,
  isInstalled: json['isInstalled'] as bool? ?? false,
  computedHash: json['computedHash'] as String?,
);

Map<String, dynamic> _$SkillEntryToJson(SkillEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'source': instance.source,
      'sourceType': _$SkillSourceTypeEnumMap[instance.sourceType]!,
      'storeId': instance.storeId,
      'installCommand': instance.installCommand,
      'installUrl': instance.installUrl,
      'isInstalled': instance.isInstalled,
      'computedHash': instance.computedHash,
    };

const _$SkillSourceTypeEnumMap = {
  SkillSourceType.github: 'github',
  SkillSourceType.url: 'url',
  SkillSourceType.installScript: 'installScript',
  SkillSourceType.local: 'local',
};
