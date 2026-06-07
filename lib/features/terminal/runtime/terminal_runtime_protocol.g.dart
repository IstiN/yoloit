// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_runtime_protocol.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TerminalRuntimeSession _$TerminalRuntimeSessionFromJson(
  Map<String, dynamic> json,
) => TerminalRuntimeSession(
  id: json['id'] as String,
  cwd: json['cwd'] as String,
  command: json['command'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  alive: json['alive'] as bool,
  title: json['title'] as String?,
  pid: (json['pid'] as num?)?.toInt(),
);

Map<String, dynamic> _$TerminalRuntimeSessionToJson(
  TerminalRuntimeSession instance,
) => <String, dynamic>{
  'id': instance.id,
  'cwd': instance.cwd,
  'command': instance.command,
  'createdAt': instance.createdAt.toIso8601String(),
  'alive': instance.alive,
  'title': instance.title,
  'pid': instance.pid,
};

TerminalRuntimeEvent _$TerminalRuntimeEventFromJson(
  Map<String, dynamic> json,
) => TerminalRuntimeEvent(
  sessionId: json['sessionId'] as String,
  type: $enumDecode(_$TerminalRuntimeEventTypeEnumMap, json['type']),
  data: json['data'] as String?,
  exitCode: (json['exitCode'] as num?)?.toInt(),
  message: json['message'] as String?,
);

Map<String, dynamic> _$TerminalRuntimeEventToJson(
  TerminalRuntimeEvent instance,
) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'type': _$TerminalRuntimeEventTypeEnumMap[instance.type]!,
  'data': instance.data,
  'exitCode': instance.exitCode,
  'message': instance.message,
};

const _$TerminalRuntimeEventTypeEnumMap = {
  TerminalRuntimeEventType.output: 'output',
  TerminalRuntimeEventType.exit: 'exit',
  TerminalRuntimeEventType.resizeAck: 'resizeAck',
  TerminalRuntimeEventType.error: 'error',
};
