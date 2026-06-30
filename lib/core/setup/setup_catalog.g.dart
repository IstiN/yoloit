// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setup_catalog.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetupRuntimeInfo _$SetupRuntimeInfoFromJson(Map<String, dynamic> json) =>
    SetupRuntimeInfo(
      os: $enumDecode(_$SetupTargetOsEnumMap, json['os']),
      osLabel: json['osLabel'] as String,
      versionLabel: json['versionLabel'] as String,
      packageManager: json['packageManager'] as String,
      homeDirectory: json['homeDirectory'] as String,
    );

Map<String, dynamic> _$SetupRuntimeInfoToJson(SetupRuntimeInfo instance) =>
    <String, dynamic>{
      'os': _$SetupTargetOsEnumMap[instance.os]!,
      'osLabel': instance.osLabel,
      'versionLabel': instance.versionLabel,
      'packageManager': instance.packageManager,
      'homeDirectory': instance.homeDirectory,
    };

const _$SetupTargetOsEnumMap = {
  SetupTargetOs.macos: 'macos',
  SetupTargetOs.linux: 'linux',
  SetupTargetOs.windows: 'windows',
  SetupTargetOs.unknown: 'unknown',
};

SetupInstallAction _$SetupInstallActionFromJson(Map<String, dynamic> json) =>
    SetupInstallAction(
      command: json['command'] as String,
      requiresInteraction: json['requiresInteraction'] as bool? ?? false,
    );

Map<String, dynamic> _$SetupInstallActionToJson(SetupInstallAction instance) =>
    <String, dynamic>{
      'command': instance.command,
      'requiresInteraction': instance.requiresInteraction,
    };

SetupPackageStatus _$SetupPackageStatusFromJson(Map<String, dynamic> json) =>
    SetupPackageStatus(
      id: json['id'] as String,
      name: json['name'] as String,
      category: $enumDecode(_$SetupPackageCategoryEnumMap, json['category']),
      description: json['description'] as String,
      command: json['command'] as String,
      required: json['required'] as bool,
      available: json['available'] as bool,
      version: json['version'] as String?,
      installAction: json['installAction'] == null
          ? null
          : SetupInstallAction.fromJson(
              json['installAction'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$SetupPackageStatusToJson(SetupPackageStatus instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': _$SetupPackageCategoryEnumMap[instance.category]!,
      'description': instance.description,
      'command': instance.command,
      'required': instance.required,
      'available': instance.available,
      'version': instance.version,
      'installAction': instance.installAction?.toJson(),
    };

const _$SetupPackageCategoryEnumMap = {
  SetupPackageCategory.system: 'system',
  SetupPackageCategory.agents: 'agents',
  SetupPackageCategory.optional: 'optional',
};

SetupCheckSnapshot _$SetupCheckSnapshotFromJson(Map<String, dynamic> json) =>
    SetupCheckSnapshot(
      runtime: SetupRuntimeInfo.fromJson(
        json['runtime'] as Map<String, dynamic>,
      ),
      packages: (json['packages'] as List<dynamic>)
          .map((e) => SetupPackageStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SetupCheckSnapshotToJson(SetupCheckSnapshot instance) =>
    <String, dynamic>{
      'runtime': instance.runtime.toJson(),
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };
