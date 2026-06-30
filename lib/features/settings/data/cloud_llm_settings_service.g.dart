// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_llm_settings_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CloudLlmConfig _$CloudLlmConfigFromJson(Map<String, dynamic> json) =>
    CloudLlmConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      extraHeaders:
          (json['extraHeaders'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
    );

Map<String, dynamic> _$CloudLlmConfigToJson(CloudLlmConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'baseUrl': instance.baseUrl,
      'apiKey': instance.apiKey,
      'model': instance.model,
      'extraHeaders': instance.extraHeaders,
    };

VoiceSettings _$VoiceSettingsFromJson(Map<String, dynamic> json) =>
    VoiceSettings(
      useCloudAsr: json['useCloudAsr'] as bool? ?? true,
      convertWavToMp3: json['convertWavToMp3'] as bool? ?? false,
      useChatModelForCloudAsr: json['useChatModelForCloudAsr'] as bool? ?? true,
      cloudAsrConfigId: json['cloudAsrConfigId'] as String?,
      cloudAsrModel: json['cloudAsrModel'] as String?,
    );

Map<String, dynamic> _$VoiceSettingsToJson(VoiceSettings instance) =>
    <String, dynamic>{
      'useCloudAsr': instance.useCloudAsr,
      'convertWavToMp3': instance.convertWavToMp3,
      'useChatModelForCloudAsr': instance.useChatModelForCloudAsr,
      'cloudAsrConfigId': instance.cloudAsrConfigId,
      'cloudAsrModel': instance.cloudAsrModel,
    };
