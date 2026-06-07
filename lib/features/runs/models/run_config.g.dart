// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RunQuickAction _$RunQuickActionFromJson(Map<String, dynamic> json) =>
    RunQuickAction(
      id: json['id'] as String,
      label: json['label'] as String,
      icon: json['icon'] as String,
      command: json['command'] as String,
      appendNewline: json['appendNewline'] as bool? ?? false,
    );

Map<String, dynamic> _$RunQuickActionToJson(RunQuickAction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'icon': instance.icon,
      'command': instance.command,
      'appendNewline': instance.appendNewline,
    };

RunConfig _$RunConfigFromJson(Map<String, dynamic> json) => RunConfig(
  id: json['id'] as String,
  name: json['name'] as String,
  command: json['command'] as String,
  group: json['group'] as String? ?? 'default',
  workingDir: json['workingDir'] as String?,
  env:
      (json['env'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  color: const ColorNullableJsonConverter().fromJson(
    (json['color'] as num?)?.toInt(),
  ),
  isFlutterRun: json['isFlutterRun'] as bool? ?? false,
  quickActions:
      (json['quickActions'] as List<dynamic>?)
          ?.map((e) => RunQuickAction.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$RunConfigToJson(RunConfig instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'command': instance.command,
  'group': instance.group,
  'workingDir': instance.workingDir,
  'env': instance.env,
  'color': const ColorNullableJsonConverter().toJson(instance.color),
  'isFlutterRun': instance.isFlutterRun,
  'quickActions': instance.quickActions,
};
