// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  id: json['id'] as String? ?? '',
  role: $enumDecodeNullable(_$ChatRoleEnumMap, json['role']) ?? ChatRole.system,
  content: json['content'] as String? ?? '',
  timestamp:
      json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
  toolCalls:
      (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => ChatToolCall.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  toolName: json['toolName'] as String?,
  toolCallId: json['toolCallId'] as String?,
  isStreaming: json['isStreaming'] as bool? ?? false,
  tokenUsage:
      json['tokenUsage'] == null
          ? null
          : ChatTokenUsage.fromJson(json['tokenUsage'] as Map<String, dynamic>),
  metadata: json['metadata'] as Map<String, dynamic>?,
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': _$ChatRoleEnumMap[instance.role]!,
      'content': instance.content,
      'timestamp': instance.timestamp?.toIso8601String(),
      'toolCalls': instance.toolCalls.map((e) => e.toJson()).toList(),
      'toolName': instance.toolName,
      'toolCallId': instance.toolCallId,
      'tokenUsage': instance.tokenUsage?.toJson(),
      'metadata': instance.metadata,
      'attachments': instance.attachments,
    };

const _$ChatRoleEnumMap = {
  ChatRole.user: 'user',
  ChatRole.assistant: 'assistant',
  ChatRole.system: 'system',
  ChatRole.tool: 'tool',
};

ChatToolCall _$ChatToolCallFromJson(Map<String, dynamic> json) => ChatToolCall(
  toolCallId: json['toolCallId'] as String? ?? '',
  toolName: json['toolName'] as String? ?? '',
  arguments: json['arguments'] as Map<String, dynamic>? ?? {},
  result: json['result'] as String?,
  isRunning: json['isRunning'] as bool? ?? false,
  success: json['success'] as bool?,
);

Map<String, dynamic> _$ChatToolCallToJson(ChatToolCall instance) =>
    <String, dynamic>{
      'toolCallId': instance.toolCallId,
      'toolName': instance.toolName,
      'arguments': instance.arguments,
      'result': instance.result,
      'success': instance.success,
    };

ChatTokenUsage _$ChatTokenUsageFromJson(Map<String, dynamic> json) =>
    ChatTokenUsage(
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      premiumRequests: (json['premiumRequests'] as num?)?.toInt() ?? 0,
      totalApiDurationMs: (json['totalApiDurationMs'] as num?)?.toInt() ?? 0,
      sessionDurationMs: (json['sessionDurationMs'] as num?)?.toInt() ?? 0,
      linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
      linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ChatTokenUsageToJson(ChatTokenUsage instance) =>
    <String, dynamic>{
      'outputTokens': instance.outputTokens,
      'premiumRequests': instance.premiumRequests,
      'totalApiDurationMs': instance.totalApiDurationMs,
      'sessionDurationMs': instance.sessionDurationMs,
      'linesAdded': instance.linesAdded,
      'linesRemoved': instance.linesRemoved,
    };

ChatSessionConfig _$ChatSessionConfigFromJson(Map<String, dynamic> json) =>
    ChatSessionConfig(
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      provider: json['provider'] as String? ?? 'copilot',
      model: json['model'] as String? ?? 'gpt-5-mini',
      reasoningEffort: json['reasoningEffort'] as String?,
      autopilot: json['autopilot'] as bool? ?? false,
      mode: json['mode'] as String?,
      maxAutopilotContinues:
          (json['maxAutopilotContinues'] as num?)?.toInt() ?? 99,
      customArgs:
          (json['customArgs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      envGroupIds:
          (json['envGroupIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      disabledLocalToolNames:
          (json['disabledLocalToolNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$ChatSessionConfigToJson(ChatSessionConfig instance) =>
    <String, dynamic>{
      'sessionName': instance.sessionName,
      'workingDir': instance.workingDir,
      'provider': instance.provider,
      'model': instance.model,
      'reasoningEffort': instance.reasoningEffort,
      'autopilot': instance.autopilot,
      'mode': instance.mode,
      'maxAutopilotContinues': instance.maxAutopilotContinues,
      'customArgs': instance.customArgs,
      'envGroupIds': instance.envGroupIds,
      'disabledLocalToolNames': instance.disabledLocalToolNames,
    };

ChatModelInfo _$ChatModelInfoFromJson(Map<String, dynamic> json) =>
    ChatModelInfo(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      costMultiplier: (json['costMultiplier'] as num?)?.toDouble(),
      isDefault: json['isDefault'] as bool? ?? false,
      inputCostPerMillion: (json['inputCostPerMillion'] as num?)?.toDouble(),
      outputCostPerMillion: (json['outputCostPerMillion'] as num?)?.toDouble(),
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      providerGroup: json['providerGroup'] as String?,
    );

Map<String, dynamic> _$ChatModelInfoToJson(ChatModelInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'costMultiplier': instance.costMultiplier,
      'isDefault': instance.isDefault,
      'inputCostPerMillion': instance.inputCostPerMillion,
      'outputCostPerMillion': instance.outputCostPerMillion,
      'contextWindow': instance.contextWindow,
      'providerGroup': instance.providerGroup,
    };
