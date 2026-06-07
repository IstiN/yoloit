// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skill_store_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SkillStore _$SkillStoreFromJson(Map<String, dynamic> json) => SkillStore(
  id: json['id'] as String,
  name: json['name'] as String,
  type: $enumDecode(_$SkillStoreTypeEnumMap, json['type']),
  url: json['url'] as String,
  isBuiltIn: json['isBuiltIn'] as bool? ?? false,
);

Map<String, dynamic> _$SkillStoreToJson(SkillStore instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$SkillStoreTypeEnumMap[instance.type]!,
      'url': instance.url,
      'isBuiltIn': instance.isBuiltIn,
    };

const _$SkillStoreTypeEnumMap = {
  SkillStoreType.github: 'github',
  SkillStoreType.url: 'url',
  SkillStoreType.installScript: 'installScript',
  SkillStoreType.local: 'local',
};

SkillsStoreConfig _$SkillsStoreConfigFromJson(Map<String, dynamic> json) =>
    SkillsStoreConfig(
      stores:
          (json['stores'] as List<dynamic>)
              .map((e) => SkillStore.fromJson(e as Map<String, dynamic>))
              .toList(),
      catalog:
          (json['catalog'] as List<dynamic>?)
              ?.map((e) => SkillEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$SkillsStoreConfigToJson(SkillsStoreConfig instance) =>
    <String, dynamic>{'stores': instance.stores, 'catalog': instance.catalog};
