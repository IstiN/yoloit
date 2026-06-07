// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_config_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgentConfig _$AgentConfigFromJson(Map<String, dynamic> json) => AgentConfig(
  id: json['id'] as String,
  displayName: json['displayName'] as String,
  iconLabel: json['iconLabel'] as String,
  launchCommand: json['launchCommand'] as String,
  visible: json['visible'] as bool,
  isBuiltIn: json['isBuiltIn'] as bool,
  streamAdapter: json['streamAdapter'] as String?,
  passDefaultArgs: json['passDefaultArgs'] as bool? ?? true,
  disableModel: json['disableModel'] as bool? ?? false,
  defaultModel: json['defaultModel'] as String?,
  asrMode: json['asrMode'] as String? ?? 'default',
  asrCloudConfigId: json['asrCloudConfigId'] as String?,
  asrCloudModel: json['asrCloudModel'] as String?,
);

Map<String, dynamic> _$AgentConfigToJson(AgentConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'iconLabel': instance.iconLabel,
      'launchCommand': instance.launchCommand,
      'visible': instance.visible,
      'isBuiltIn': instance.isBuiltIn,
      'streamAdapter': instance.streamAdapter,
      'passDefaultArgs': instance.passDefaultArgs,
      'disableModel': instance.disableModel,
      'defaultModel': instance.defaultModel,
      'asrMode': instance.asrMode,
      'asrCloudConfigId': instance.asrCloudConfigId,
      'asrCloudModel': instance.asrCloudModel,
    };
