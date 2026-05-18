import 'package:equatable/equatable.dart';

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
    this.metadata,
    this.attachments = const [],
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

  /// Extra metadata (e.g. ask_user choices).
  final Map<String, dynamic>? metadata;

  /// File paths attached to this message (images, documents, etc.).
  final List<String> attachments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (toolCalls.isNotEmpty)
      'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    if (toolName != null) 'toolName': toolName,
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (tokenUsage != null) 'tokenUsage': tokenUsage!.toJson(),
    if (metadata != null) 'metadata': metadata,
    if (attachments.isNotEmpty) 'attachments': attachments,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String? ?? 'system';
    final role = ChatRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => ChatRole.system,
    );
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: role,
      content: json['content'] as String? ?? '',
      timestamp:
          json['timestamp'] != null
              ? DateTime.tryParse(json['timestamp'] as String)
              : null,
      toolCalls:
          (json['toolCalls'] as List?)
              ?.map(
                (e) =>
                    ChatToolCall.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      toolName: json['toolName'] as String?,
      toolCallId: json['toolCallId'] as String?,
      tokenUsage:
          json['tokenUsage'] is Map
              ? ChatTokenUsage.fromJson(
                Map<String, dynamic>.from(json['tokenUsage'] as Map),
              )
              : null,
      metadata:
          json['metadata'] is Map
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : null,
      attachments: (json['attachments'] as List?)?.cast<String>() ?? const [],
    );
  }

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
    Map<String, dynamic>? metadata,
    List<String>? attachments,
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
      metadata: metadata ?? this.metadata,
      attachments: attachments ?? this.attachments,
    );
  }

  @override
  List<Object?> get props => [
    id,
    role,
    content,
    timestamp,
    toolCalls,
    toolName,
    toolCallId,
    isStreaming,
    tokenUsage,
    metadata,
    attachments,
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

  Map<String, dynamic> toJson() => {
    'toolCallId': toolCallId,
    'toolName': toolName,
    'arguments': arguments,
    if (result != null) 'result': result,
    if (success != null) 'success': success,
  };

  factory ChatToolCall.fromJson(Map<String, dynamic> json) => ChatToolCall(
    toolCallId: json['toolCallId'] as String? ?? '',
    toolName: json['toolName'] as String? ?? '',
    arguments:
        json['arguments'] is Map
            ? Map<String, dynamic>.from(json['arguments'] as Map)
            : <String, dynamic>{},
    result: json['result'] as String?,
    success: json['success'] as bool?,
  );

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
    toolCallId,
    toolName,
    arguments,
    result,
    isRunning,
    success,
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

  Map<String, dynamic> toJson() => {
    'outputTokens': outputTokens,
    'premiumRequests': premiumRequests,
    'totalApiDurationMs': totalApiDurationMs,
    'sessionDurationMs': sessionDurationMs,
    'linesAdded': linesAdded,
    'linesRemoved': linesRemoved,
  };

  factory ChatTokenUsage.fromJson(Map<String, dynamic> json) => ChatTokenUsage(
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    premiumRequests: (json['premiumRequests'] as num?)?.toInt() ?? 0,
    totalApiDurationMs: (json['totalApiDurationMs'] as num?)?.toInt() ?? 0,
    sessionDurationMs: (json['sessionDurationMs'] as num?)?.toInt() ?? 0,
    linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
    linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [
    outputTokens,
    premiumRequests,
    totalApiDurationMs,
    sessionDurationMs,
    linesAdded,
    linesRemoved,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat event — parsed from JSON lines
// ─────────────────────────────────────────────────────────────────────────────

enum ChatEventType {
  sessionStatus, // mcp_server_status, servers_loaded, skills_loaded, tools_updated
  userMessage, // user.message
  assistantTurnStart, // assistant.turn_start
  assistantMessageStart, // assistant.message_start
  assistantDelta, // assistant.message_delta
  assistantMessage, // assistant.message (complete)
  assistantTurnEnd, // assistant.turn_end
  toolStart, // tool.execution_start
  toolComplete, // tool.execution_complete
  askUser, // ask_user.question
  result, // result (session complete)
  // Sub-agent events (from events.jsonl watcher)
  subagentStarted, // subagent.started
  subagentCompleted, // subagent.completed
  subagentToolStart, // tool.execution_start with parentToolCallId (inside sub-agent)
  subagentToolComplete, // tool.execution_complete with parentToolCallId (inside sub-agent)
  subagentMessage, // assistant.message emitted by a sub-agent
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
    var data = Map<String, dynamic>.from(json['data'] as Map? ?? const {});
    final ephemeral = json['ephemeral'] as bool? ?? false;

    final type = _parseEventType(rawType);

    // For 'result' events, usage/sessionId/exitCode are at the top level
    if (type == ChatEventType.result) {
      data = Map<String, dynamic>.from(json);
      data.remove('type');
      data.remove('timestamp');
    }

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

  /// For sub-agent events — the agent ID (= toolCallId of the `task` call).
  String? get agentId => data['agentId'] as String?;

  /// For sub-agent tool events — the parent tool call ID.
  String? get parentToolCallId => data['parentToolCallId'] as String?;

  /// For subagent.started / subagent.completed — the agent display name.
  String? get agentName =>
      (data['agentDisplayName'] as String?)?.trim().isNotEmpty == true
          ? (data['agentDisplayName'] as String?)?.trim()
          : (data['agentName'] as String?)?.trim();

  /// For subagent.started — the agent description.
  String? get agentDescription =>
      (data['agentDescription'] as String?)?.trim();

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
  List<Object?> get props => [
    type,
    rawType,
    data,
    id,
    timestamp,
    parentId,
    ephemeral,
  ];
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
    this.reasoningEffort,
    this.autopilot = false,
    this.mode,
    this.maxAutopilotContinues = 99,
    this.customArgs = const [],
    this.envGroupIds = const [],
    this.disabledLocalToolNames = const [],
  });

  final String sessionName;
  final String workingDir;

  /// Provider identifier (e.g. 'copilot', 'cursor', 'claude', 'local').
  final String provider;

  /// Model to use.
  final String model;

  /// Reasoning effort level: low, medium, high, xhigh (null = default).
  final String? reasoningEffort;

  /// Whether to run in autopilot mode (--autopilot flag).
  final bool autopilot;

  /// Agent mode: interactive, plan, autopilot (null = default/interactive).
  final String? mode;

  /// Max autopilot continuation messages.
  final int maxAutopilotContinues;

  /// Custom extra CLI arguments (provider-specific).
  final List<String> customArgs;

  /// Global env groups selected for this session. Last selected group wins.
  final List<String> envGroupIds;

  /// Local YoLoIT tool function names disabled for this chat session.
  final List<String> disabledLocalToolNames;

  Map<String, dynamic> toJson() => {
    'sessionName': sessionName,
    'workingDir': workingDir,
    'provider': provider,
    'model': model,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    'autopilot': autopilot,
    if (mode != null) 'mode': mode,
    'maxAutopilotContinues': maxAutopilotContinues,
    if (customArgs.isNotEmpty) 'customArgs': customArgs,
    if (envGroupIds.isNotEmpty) 'envGroupIds': envGroupIds,
    if (disabledLocalToolNames.isNotEmpty)
      'disabledLocalToolNames': disabledLocalToolNames,
  };

  factory ChatSessionConfig.fromJson(Map<String, dynamic> json) {
    return ChatSessionConfig(
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      provider: json['provider'] as String? ?? 'copilot',
      model: json['model'] as String? ?? 'gpt-5-mini',
      reasoningEffort: json['reasoningEffort'] as String?,
      autopilot: json['autopilot'] as bool? ?? false,
      mode: json['mode'] as String?,
      maxAutopilotContinues: json['maxAutopilotContinues'] as int? ?? 99,
      customArgs: (json['customArgs'] as List?)?.cast<String>() ?? const [],
      envGroupIds: (json['envGroupIds'] as List?)?.cast<String>() ?? const [],
      disabledLocalToolNames:
          (json['disabledLocalToolNames'] as List?)?.cast<String>() ?? const [],
    );
  }

  ChatSessionConfig copyWith({
    String? sessionName,
    String? workingDir,
    String? provider,
    String? model,
    String? Function()? reasoningEffort,
    bool? autopilot,
    String? Function()? mode,
    int? maxAutopilotContinues,
    List<String>? customArgs,
    List<String>? envGroupIds,
    List<String>? disabledLocalToolNames,
  }) {
    return ChatSessionConfig(
      sessionName: sessionName ?? this.sessionName,
      workingDir: workingDir ?? this.workingDir,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      reasoningEffort:
          reasoningEffort != null ? reasoningEffort() : this.reasoningEffort,
      autopilot: autopilot ?? this.autopilot,
      mode: mode != null ? mode() : this.mode,
      maxAutopilotContinues:
          maxAutopilotContinues ?? this.maxAutopilotContinues,
      customArgs: customArgs ?? this.customArgs,
      envGroupIds: envGroupIds ?? this.envGroupIds,
      disabledLocalToolNames:
          disabledLocalToolNames ?? this.disabledLocalToolNames,
    );
  }

  @override
  List<Object?> get props => [
    sessionName,
    workingDir,
    provider,
    model,
    reasoningEffort,
    autopilot,
    mode,
    maxAutopilotContinues,
    customArgs,
    envGroupIds,
    disabledLocalToolNames,
  ];
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
  ChatModelInfo(
    id: 'claude-sonnet-4.6',
    displayName: 'Claude Sonnet 4.6',
    costMultiplier: 1,
    isDefault: true,
  ),
  ChatModelInfo(
    id: 'claude-sonnet-4.5',
    displayName: 'Claude Sonnet 4.5',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'claude-haiku-4.5',
    displayName: 'Claude Haiku 4.5',
    costMultiplier: 0.33,
  ),
  ChatModelInfo(
    id: 'claude-opus-4.7',
    displayName: 'Claude Opus 4.7',
    costMultiplier: 15,
  ),
  ChatModelInfo(
    id: 'claude-opus-4.6',
    displayName: 'Claude Opus 4.6',
    costMultiplier: 3,
  ),
  ChatModelInfo(
    id: 'claude-opus-4.5',
    displayName: 'Claude Opus 4.5',
    costMultiplier: 3,
  ),
  ChatModelInfo(id: 'gpt-5.5', displayName: 'GPT-5.5', costMultiplier: 7.5),
  ChatModelInfo(id: 'gpt-5.4', displayName: 'GPT-5.4', costMultiplier: 1),
  ChatModelInfo(
    id: 'gpt-5.3-codex',
    displayName: 'GPT-5.3-Codex',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'gpt-5.2-codex',
    displayName: 'GPT-5.2-Codex',
    costMultiplier: 1,
  ),
  ChatModelInfo(id: 'gpt-5.2', displayName: 'GPT-5.2', costMultiplier: 1),
  ChatModelInfo(
    id: 'gpt-5.4-mini',
    displayName: 'GPT-5.4 mini',
    costMultiplier: 0.33,
  ),
  ChatModelInfo(id: 'gpt-5-mini', displayName: 'GPT-5 mini', costMultiplier: 0),
  ChatModelInfo(id: 'gpt-4.1', displayName: 'GPT-4.1', costMultiplier: 0),
];

/// Cursor Agent available models.
const List<ChatModelInfo> kCursorModels = [
  // Fast / cheap
  ChatModelInfo(
    id: 'gpt-5.4-nano-medium',
    displayName: 'GPT-5.4 Nano',
    costMultiplier: 0.1,
    isDefault: true,
  ),
  ChatModelInfo(
    id: 'gpt-5.4-mini-medium',
    displayName: 'GPT-5.4 Mini',
    costMultiplier: 0.2,
  ),
  ChatModelInfo(
    id: 'gpt-5-mini',
    displayName: 'GPT-5 Mini',
    costMultiplier: 0.2,
  ),
  ChatModelInfo(
    id: 'gemini-3-flash',
    displayName: 'Gemini 3 Flash',
    costMultiplier: 0.1,
  ),

  // Standard
  ChatModelInfo(
    id: 'gpt-5.4-medium',
    displayName: 'GPT-5.4',
    costMultiplier: 1,
  ),
  ChatModelInfo(id: 'gpt-5.2', displayName: 'GPT-5.2', costMultiplier: 1),
  ChatModelInfo(id: 'gpt-5.1', displayName: 'GPT-5.1', costMultiplier: 1),
  ChatModelInfo(
    id: 'claude-4.6-sonnet-medium',
    displayName: 'Sonnet 4.6',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'claude-4.5-sonnet',
    displayName: 'Sonnet 4.5',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'claude-4-sonnet',
    displayName: 'Sonnet 4',
    costMultiplier: 1,
  ),
  ChatModelInfo(id: 'kimi-k2.5', displayName: 'Kimi K2.5', costMultiplier: 0.5),
  ChatModelInfo(
    id: 'gemini-3.1-pro',
    displayName: 'Gemini 3.1 Pro',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'gpt-5.3-codex',
    displayName: 'Codex 5.3',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'gpt-5.2-codex',
    displayName: 'Codex 5.2',
    costMultiplier: 1,
  ),

  // Premium
  ChatModelInfo(
    id: 'gpt-5.5-medium',
    displayName: 'GPT-5.5',
    costMultiplier: 5,
  ),
  ChatModelInfo(id: 'grok-4.3', displayName: 'Grok 4.3', costMultiplier: 2),
  ChatModelInfo(
    id: 'claude-opus-4-7-medium',
    displayName: 'Opus 4.7',
    costMultiplier: 5,
  ),
  ChatModelInfo(
    id: 'claude-4.6-opus-high',
    displayName: 'Opus 4.6',
    costMultiplier: 3,
  ),
  ChatModelInfo(
    id: 'claude-4.5-opus-high',
    displayName: 'Opus 4.5',
    costMultiplier: 3,
  ),

  // Thinking models
  ChatModelInfo(
    id: 'claude-4.6-sonnet-medium-thinking',
    displayName: 'Sonnet 4.6 Thinking',
    costMultiplier: 2,
  ),
  ChatModelInfo(
    id: 'claude-4.5-sonnet-thinking',
    displayName: 'Sonnet 4.5 Thinking',
    costMultiplier: 2,
  ),
  ChatModelInfo(
    id: 'claude-opus-4-7-thinking-medium',
    displayName: 'Opus 4.7 Thinking',
    costMultiplier: 8,
  ),
  ChatModelInfo(
    id: 'claude-4.6-opus-high-thinking',
    displayName: 'Opus 4.6 Thinking',
    costMultiplier: 6,
  ),
  ChatModelInfo(id: 'composer-2', displayName: 'Composer 2', costMultiplier: 1),
];

/// Local on-device chat models backed by flutter_local_models.
const List<ChatModelInfo> kLocalModels = [
  ChatModelInfo(
    id: 'gemma4-e2b-it-4bit',
    displayName: 'Gemma 4 E2B IT 4bit',
    costMultiplier: 0,
    isDefault: true,
  ),
  ChatModelInfo(
    id: 'qwen3-4b-instruct-4bit',
    displayName: 'Qwen3 4B Instruct 4bit (latest)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'qwen3-4b-instruct-2507-4bit',
    displayName: 'Qwen3 4B Instruct 4bit',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'qwen3-8b-4bit',
    displayName: 'Qwen3 8B 4bit',
    costMultiplier: 0,
  ),
];


/// OpenCode models (providerID/modelID format, from `opencode models`).
const List<ChatModelInfo> kOpencodeModels = [
  // ── OpenCode built-in free models ─────────────────────────────────────
  ChatModelInfo(
    id: 'opencode/qwen3.6-plus-free',
    displayName: 'Qwen 3.6 Plus (Free)',
    costMultiplier: 0,
    isDefault: true,
  ),
  ChatModelInfo(
    id: 'opencode/big-pickle',
    displayName: 'Big Pickle (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'opencode/deepseek-v4-flash-free',
    displayName: 'DeepSeek V4 Flash (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'opencode/nemotron-3-super-free',
    displayName: 'Nemotron 3 Super (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'opencode/minimax-m2.5-free',
    displayName: 'MiniMax M2.5 (Free)',
    costMultiplier: 0,
  ),

  // ── Anthropic ─────────────────────────────────────────────────────────
  ChatModelInfo(
    id: 'anthropic/claude-sonnet-4-5',
    displayName: 'Claude Sonnet 4.5',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'anthropic/claude-opus-4-7',
    displayName: 'Claude Opus 4.7',
    costMultiplier: 15,
  ),
  ChatModelInfo(
    id: 'anthropic/claude-haiku-4-5',
    displayName: 'Claude Haiku 4.5',
    costMultiplier: 0.33,
  ),
  ChatModelInfo(
    id: 'anthropic/claude-sonnet-4',
    displayName: 'Claude Sonnet 4',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'anthropic/claude-opus-4-5',
    displayName: 'Claude Opus 4.5',
    costMultiplier: 3,
  ),

  // ── OpenAI ────────────────────────────────────────────────────────────
  ChatModelInfo(id: 'openai/gpt-4o', displayName: 'GPT-4o', costMultiplier: 1),
  ChatModelInfo(
    id: 'openai/gpt-4.1',
    displayName: 'GPT-4.1',
    costMultiplier: 0.8,
  ),
  ChatModelInfo(
    id: 'openai/gpt-4o-mini',
    displayName: 'GPT-4o Mini',
    costMultiplier: 0.2,
  ),
  ChatModelInfo(
    id: 'openai/o3-mini',
    displayName: 'O3 Mini',
    costMultiplier: 0.4,
  ),
  ChatModelInfo(
    id: 'openai/o4-mini',
    displayName: 'O4 Mini',
    costMultiplier: 0.6,
  ),

  // ── Google ────────────────────────────────────────────────────────────
  ChatModelInfo(
    id: 'google/gemini-2.5-pro',
    displayName: 'Gemini 2.5 Pro',
    costMultiplier: 1,
  ),
  ChatModelInfo(
    id: 'google/gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash',
    costMultiplier: 0.1,
  ),

  // ── xAI Grok ─────────────────────────────────────────────────────────
  ChatModelInfo(
    id: 'xai/grok-4',
    displayName: 'Grok 4',
    costMultiplier: 2,
  ),
  ChatModelInfo(
    id: 'xai/grok-code-fast-1',
    displayName: 'Grok Code Fast',
    costMultiplier: 0.5,
  ),

  // ── OpenRouter free models ────────────────────────────────────────────
  ChatModelInfo(
    id: 'openrouter/deepseek/deepseek-chat-v3-0324:free',
    displayName: 'OR DeepSeek V3 (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/deepseek/deepseek-r1:free',
    displayName: 'OR DeepSeek R1 (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/nvidia/llama-3.1-nemotron-ultra-253b-v1:free',
    displayName: 'OR Nemotron Ultra (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/meta-llama/llama-4-maverick:free',
    displayName: 'OR Llama 4 Maverick (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/google/gemma-3-27b-it:free',
    displayName: 'OR Gemma 3 27B (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/moonshotai/kimi-k2-instruct-0905:free',
    displayName: 'OR Kimi K2 (Free)',
    costMultiplier: 0,
  ),

  // ── OpenRouter paid models ────────────────────────────────────────────
  ChatModelInfo(
    id: 'openrouter/qwen/qwen-plus',
    displayName: 'OR Qwen Plus',
    costMultiplier: 0.5,
  ),
  ChatModelInfo(
    id: 'openrouter/qwen/qwen-2.5-72b-instruct',
    displayName: 'OR Qwen 2.5 72B',
    costMultiplier: 0.3,
  ),
  ChatModelInfo(
    id: 'openrouter/meta-llama/llama-3.3-70b-instruct',
    displayName: 'OR Llama 3.3 70B',
    costMultiplier: 0.3,
  ),
  ChatModelInfo(
    id: 'openrouter/deepseek/deepseek-r1-distill-qwen-32b:free',
    displayName: 'OR DeepSeek R1 Distill (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/mistralai/mistral-small-3.1-24b-instruct:free',
    displayName: 'OR Mistral Small 3.1 (Free)',
    costMultiplier: 0,
  ),
  ChatModelInfo(
    id: 'openrouter/microsoft/phi-4-multimodal-instruct',
    displayName: 'OR Phi-4 Multimodal',
    costMultiplier: 0.2,
  ),
];
