import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chat message roles
// ─────────────────────────────────────────────────────────────────────────────

enum ChatRole { user, assistant, system, tool }

// ─────────────────────────────────────────────────────────────────────────────
// Chat message
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
    this.toolCalls = const [],
    this.toolName,
    this.toolCallId,
    this.isStreaming = false,
    this.tokenUsage,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime? timestamp;

  /// Tool calls requested by the assistant in this message.
  final List<ChatToolCall> toolCalls;

  /// For tool-role messages: which tool produced this result.
  final String? toolName;

  /// For tool-role messages: the tool call ID this result belongs to.
  final String? toolCallId;

  /// True while the message is still being streamed.
  final bool isStreaming;

  /// Token usage info (populated from the `result` event).
  final ChatTokenUsage? tokenUsage;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? timestamp,
    List<ChatToolCall>? toolCalls,
    String? toolName,
    String? toolCallId,
    bool? isStreaming,
    ChatTokenUsage? tokenUsage,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      toolName: toolName ?? this.toolName,
      toolCallId: toolCallId ?? this.toolCallId,
      isStreaming: isStreaming ?? this.isStreaming,
      tokenUsage: tokenUsage ?? this.tokenUsage,
    );
  }

  @override
  List<Object?> get props => [
    id, role, content, timestamp, toolCalls, toolName,
    toolCallId, isStreaming, tokenUsage,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool calls
// ─────────────────────────────────────────────────────────────────────────────

class ChatToolCall extends Equatable {
  const ChatToolCall({
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
    this.result,
    this.isRunning = false,
    this.success,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;

  /// Result content after execution.
  final String? result;

  /// Whether the tool is currently executing.
  final bool isRunning;

  /// Whether execution succeeded (null = not yet complete).
  final bool? success;

  ChatToolCall copyWith({
    String? toolCallId,
    String? toolName,
    Map<String, dynamic>? arguments,
    String? result,
    bool? isRunning,
    bool? success,
  }) {
    return ChatToolCall(
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      isRunning: isRunning ?? this.isRunning,
      success: success ?? this.success,
    );
  }

  @override
  List<Object?> get props => [
    toolCallId, toolName, arguments, result, isRunning, success,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Ask-user question from the agent
// ─────────────────────────────────────────────────────────────────────────────

class ChatAskUser extends Equatable {
  const ChatAskUser({
    required this.question,
    this.choices = const [],
    this.allowFreeform = true,
    this.response,
  });

  final String question;
  final List<String> choices;
  final bool allowFreeform;
  final String? response;

  ChatAskUser copyWith({String? response}) {
    return ChatAskUser(
      question: question,
      choices: choices,
      allowFreeform: allowFreeform,
      response: response ?? this.response,
    );
  }

  @override
  List<Object?> get props => [question, choices, allowFreeform, response];
}

// ─────────────────────────────────────────────────────────────────────────────
// Token usage
// ─────────────────────────────────────────────────────────────────────────────

class ChatTokenUsage extends Equatable {
  const ChatTokenUsage({
    this.outputTokens = 0,
    this.premiumRequests = 0,
    this.totalApiDurationMs = 0,
    this.sessionDurationMs = 0,
    this.linesAdded = 0,
    this.linesRemoved = 0,
  });

  final int outputTokens;
  final int premiumRequests;
  final int totalApiDurationMs;
  final int sessionDurationMs;
  final int linesAdded;
  final int linesRemoved;

  @override
  List<Object?> get props => [
    outputTokens, premiumRequests, totalApiDurationMs,
    sessionDurationMs, linesAdded, linesRemoved,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat event — parsed from JSON lines
// ─────────────────────────────────────────────────────────────────────────────

enum ChatEventType {
  sessionStatus,       // mcp_server_status, servers_loaded, skills_loaded, tools_updated
  userMessage,         // user.message
  assistantTurnStart,  // assistant.turn_start
  assistantMessageStart, // assistant.message_start
  assistantDelta,      // assistant.message_delta
  assistantMessage,    // assistant.message (complete)
  assistantTurnEnd,    // assistant.turn_end
  toolStart,           // tool.execution_start
  toolComplete,        // tool.execution_complete
  askUser,             // ask_user.question
  result,              // result (session complete)
  unknown,
}

class ChatEvent extends Equatable {
  const ChatEvent({
    required this.type,
    required this.rawType,
    this.data = const {},
    this.id,
    this.timestamp,
    this.parentId,
    this.ephemeral = false,
  });

  final ChatEventType type;

  /// Original `type` string from JSON.
  final String rawType;
  final Map<String, dynamic> data;
  final String? id;
  final DateTime? timestamp;
  final String? parentId;
  final bool ephemeral;

  factory ChatEvent.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String? ?? '';
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? const {});
    final ephemeral = json['ephemeral'] as bool? ?? false;

    final type = _parseEventType(rawType);
    DateTime? ts;
    final tsStr = json['timestamp'] as String?;
    if (tsStr != null) {
      ts = DateTime.tryParse(tsStr);
    }

    return ChatEvent(
      type: type,
      rawType: rawType,
      data: data,
      id: json['id'] as String?,
      timestamp: ts,
      parentId: json['parentId'] as String?,
      ephemeral: ephemeral,
    );
  }

  static ChatEventType _parseEventType(String raw) {
    switch (raw) {
      case 'session.mcp_server_status_changed':
      case 'session.mcp_servers_loaded':
      case 'session.skills_loaded':
      case 'session.tools_updated':
        return ChatEventType.sessionStatus;
      case 'user.message':
        return ChatEventType.userMessage;
      case 'assistant.turn_start':
        return ChatEventType.assistantTurnStart;
      case 'assistant.message_start':
        return ChatEventType.assistantMessageStart;
      case 'assistant.message_delta':
        return ChatEventType.assistantDelta;
      case 'assistant.message':
        return ChatEventType.assistantMessage;
      case 'assistant.turn_end':
        return ChatEventType.assistantTurnEnd;
      case 'tool.execution_start':
        return ChatEventType.toolStart;
      case 'tool.execution_complete':
        return ChatEventType.toolComplete;
      case 'ask_user.question':
        return ChatEventType.askUser;
      case 'result':
        return ChatEventType.result;
      default:
        return ChatEventType.unknown;
    }
  }

  // ── Convenience accessors ─────────────────────────────────────────────────

  /// For assistant.message_delta — the delta text content.
  String? get deltaContent => data['deltaContent'] as String?;

  /// For assistant.message — the full message content.
  String? get messageContent => data['content'] as String?;

  /// For assistant.message — the message ID.
  String? get messageId => data['messageId'] as String?;

  /// For tool.execution_start — the tool name.
  String? get toolName => data['toolName'] as String?;

  /// For tool.execution_start — the tool call ID.
  String? get toolCallId => data['toolCallId'] as String?;

  /// For tool.execution_start — the arguments.
  Map<String, dynamic>? get toolArguments =>
      data['arguments'] is Map
          ? Map<String, dynamic>.from(data['arguments'] as Map)
          : null;

  /// For tool.execution_complete — the result content.
  String? get toolResultContent {
    final result = data['result'];
    if (result is Map) return result['content'] as String?;
    return null;
  }

  /// For tool.execution_complete — success flag.
  bool? get toolSuccess => data['success'] as bool?;

  /// For result — output tokens.
  int? get outputTokens => (data['outputTokens'] as num?)?.toInt();

  /// For result — usage map.
  Map<String, dynamic>? get usageData =>
      data['usage'] is Map
          ? Map<String, dynamic>.from(data['usage'] as Map)
          : null;

  /// For assistant.message — tool requests.
  List<Map<String, dynamic>> get toolRequests {
    final raw = data['toolRequests'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  @override
  List<Object?> get props => [type, rawType, data, id, timestamp, parentId, ephemeral];
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat session config (stored in panel state)
// ─────────────────────────────────────────────────────────────────────────────

class ChatSessionConfig extends Equatable {
  const ChatSessionConfig({
    required this.sessionName,
    required this.workingDir,
    this.provider = 'copilot',
    this.model = 'gpt-5-mini',
  });

  final String sessionName;
  final String workingDir;

  /// Provider identifier (e.g. 'copilot', 'cursor', 'claude', 'local').
  final String provider;

  /// Model to use.
  final String model;

  Map<String, dynamic> toJson() => {
    'sessionName': sessionName,
    'workingDir': workingDir,
    'provider': provider,
    'model': model,
  };

  factory ChatSessionConfig.fromJson(Map<String, dynamic> json) {
    return ChatSessionConfig(
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      provider: json['provider'] as String? ?? 'copilot',
      model: json['model'] as String? ?? 'gpt-5-mini',
    );
  }

  ChatSessionConfig copyWith({
    String? sessionName,
    String? workingDir,
    String? provider,
    String? model,
  }) {
    return ChatSessionConfig(
      sessionName: sessionName ?? this.sessionName,
      workingDir: workingDir ?? this.workingDir,
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }

  @override
  List<Object?> get props => [sessionName, workingDir, provider, model];
}

// ─────────────────────────────────────────────────────────────────────────────
// Available models
// ─────────────────────────────────────────────────────────────────────────────

class ChatModelInfo {
  const ChatModelInfo({
    required this.id,
    required this.displayName,
    this.costMultiplier = 1.0,
    this.isDefault = false,
  });

  final String id;
  final String displayName;
  final double costMultiplier;
  final bool isDefault;
}

/// Copilot CLI available models.
const List<ChatModelInfo> kCopilotModels = [
  ChatModelInfo(id: 'claude-sonnet-4.6', displayName: 'Claude Sonnet 4.6', costMultiplier: 1, isDefault: true),
  ChatModelInfo(id: 'claude-sonnet-4.5', displayName: 'Claude Sonnet 4.5', costMultiplier: 1),
  ChatModelInfo(id: 'claude-haiku-4.5', displayName: 'Claude Haiku 4.5', costMultiplier: 0.33),
  ChatModelInfo(id: 'claude-opus-4.7', displayName: 'Claude Opus 4.7', costMultiplier: 15),
  ChatModelInfo(id: 'claude-opus-4.6', displayName: 'Claude Opus 4.6', costMultiplier: 3),
  ChatModelInfo(id: 'claude-opus-4.5', displayName: 'Claude Opus 4.5', costMultiplier: 3),
  ChatModelInfo(id: 'gpt-5.5', displayName: 'GPT-5.5', costMultiplier: 7.5),
  ChatModelInfo(id: 'gpt-5.4', displayName: 'GPT-5.4', costMultiplier: 1),
  ChatModelInfo(id: 'gpt-5.3-codex', displayName: 'GPT-5.3-Codex', costMultiplier: 1),
  ChatModelInfo(id: 'gpt-5.2-codex', displayName: 'GPT-5.2-Codex', costMultiplier: 1),
  ChatModelInfo(id: 'gpt-5.2', displayName: 'GPT-5.2', costMultiplier: 1),
  ChatModelInfo(id: 'gpt-5.4-mini', displayName: 'GPT-5.4 mini', costMultiplier: 0.33),
  ChatModelInfo(id: 'gpt-5-mini', displayName: 'GPT-5 mini', costMultiplier: 0),
  ChatModelInfo(id: 'gpt-4.1', displayName: 'GPT-4.1', costMultiplier: 0),
];
