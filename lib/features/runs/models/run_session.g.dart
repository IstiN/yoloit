// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RunOutputLine _$RunOutputLineFromJson(Map<String, dynamic> json) =>
    RunOutputLine(
      text: json['text'] as String,
      isError: json['isError'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$RunOutputLineToJson(RunOutputLine instance) =>
    <String, dynamic>{
      'text': instance.text,
      'isError': instance.isError,
      'timestamp': instance.timestamp.toIso8601String(),
    };

RunSession _$RunSessionFromJson(Map<String, dynamic> json) => RunSession(
  id: json['id'] as String,
  config: RunConfig.fromJson(json['config'] as Map<String, dynamic>),
  workspacePath: json['workspacePath'] as String,
  status:
      $enumDecodeNullable(_$RunStatusEnumMap, json['status']) ?? RunStatus.idle,
  output:
      (json['output'] as List<dynamic>?)
          ?.map((e) => RunOutputLine.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  exitCode: (json['exitCode'] as num?)?.toInt(),
  startedAt: json['startedAt'] == null
      ? null
      : DateTime.parse(json['startedAt'] as String),
);

Map<String, dynamic> _$RunSessionToJson(RunSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'config': instance.config,
      'workspacePath': instance.workspacePath,
      'status': _$RunStatusEnumMap[instance.status]!,
      'output': instance.output,
      'exitCode': instance.exitCode,
      'startedAt': instance.startedAt?.toIso8601String(),
    };

const _$RunStatusEnumMap = {
  RunStatus.idle: 'idle',
  RunStatus.running: 'running',
  RunStatus.stopped: 'stopped',
  RunStatus.failed: 'failed',
};
