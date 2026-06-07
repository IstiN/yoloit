// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_panel_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BoardTerminalConfig _$BoardTerminalConfigFromJson(Map<String, dynamic> json) =>
    BoardTerminalConfig(
      sessionId: json['sessionId'] as String,
      sessionName: json['sessionName'] as String,
      workingDir: json['workingDir'] as String,
      envGroupIds:
          (json['envGroupIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$BoardTerminalConfigToJson(
  BoardTerminalConfig instance,
) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'sessionName': instance.sessionName,
  'workingDir': instance.workingDir,
  'envGroupIds': instance.envGroupIds,
};
