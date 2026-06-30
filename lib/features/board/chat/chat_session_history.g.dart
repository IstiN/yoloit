// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_session_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatSessionEntry _$ChatSessionEntryFromJson(Map<String, dynamic> json) =>
    ChatSessionEntry(
      id: json['id'] as String? ?? '',
      sessionName: json['sessionName'] as String? ?? '',
      provider: json['provider'] as String? ?? 'copilot',
      model: json['model'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      createdAt: ChatSessionEntry._dateTimeFromJson(json['createdAt']),
      envGroupIds:
          (json['envGroupIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt'] as String),
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ChatSessionEntryToJson(ChatSessionEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sessionName': instance.sessionName,
      'provider': instance.provider,
      'model': instance.model,
      'workingDir': instance.workingDir,
      'envGroupIds': instance.envGroupIds,
      'createdAt': ChatSessionEntry._dateTimeToJson(instance.createdAt),
      'lastMessageAt': instance.lastMessageAt?.toIso8601String(),
      'messageCount': instance.messageCount,
    };
