// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'board_terminal_session_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BoardTerminalSessionEntry _$BoardTerminalSessionEntryFromJson(
  Map<String, dynamic> json,
) => BoardTerminalSessionEntry(
  id: json['id'] as String,
  sessionName: json['sessionName'] as String,
  workingDir: json['workingDir'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  envGroupIds:
      (json['envGroupIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  lastActiveAt: json['lastActiveAt'] == null
      ? null
      : DateTime.parse(json['lastActiveAt'] as String),
);

Map<String, dynamic> _$BoardTerminalSessionEntryToJson(
  BoardTerminalSessionEntry instance,
) => <String, dynamic>{
  'id': instance.id,
  'sessionName': instance.sessionName,
  'workingDir': instance.workingDir,
  'envGroupIds': instance.envGroupIds,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastActiveAt': instance.lastActiveAt?.toIso8601String(),
};
