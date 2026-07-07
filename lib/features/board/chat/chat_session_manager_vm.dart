import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_core.dart';
import 'package:yoloit/features/board/chat/chat_session_manager_mixin.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/codex_cli_provider.dart';
import 'package:yoloit/features/board/chat/copilot_cli_provider.dart';
import 'package:yoloit/features/board/chat/cursor_agent_provider.dart';
import 'package:yoloit/features/board/chat/kimi_cli_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/opencode_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

/// Singleton service that manages all active chat sessions.
///
/// Sessions survive widget lifecycle — the UI attaches/detaches as needed.
/// The CLI handler can create sessions and send messages directly.
class ChatSessionManager with ChatSessionManagerMixin {
  ChatSessionManager._({
    this.providerFactory,
  });
  static final ChatSessionManager instance = ChatSessionManager._(
    providerFactory: _createProvider,
  );

  /// For testing: create an isolated instance.
  factory ChatSessionManager.testInstance({
    ChatProvider Function(String providerId)? providerFactory,
  }) => ChatSessionManager._(providerFactory: providerFactory);

  @override
  final ChatProvider Function(String providerId)? providerFactory;
  @override
  final Map<String, ChatSession> sessions = {};

  @override
  ChatSession getOrCreate(String panelId, ChatSessionConfig config) =>
      super.getOrCreate(panelId, config);

  // ── VM provider factory ─────────────────────────────────────────────────

  static ChatProvider _createProvider(String providerId) {
    if (providerId.startsWith('cloud:')) {
      return _createCloudProvider(providerId);
    }
    if (providerId == 'local') {
      return LocalLlmProvider();
    }
    final agentConfig = AgentConfigService.instance.configForAgent(providerId);
    final adapter = agentConfig?.streamAdapter ?? providerId;
    return switch (adapter) {
      'codex' => CodexCliProvider(agentId: providerId),
      'cursor' => CursorAgentProvider(agentId: providerId),
      'kimi' => KimiCliProvider(agentId: providerId),
      'opencode' => _createOpencodeProvider(providerId),
      _ => CopilotCliProvider(agentId: providerId),
    };
  }

  static ChatProvider _createCloudProvider(String providerId) {
    final configId = providerId.substring(6);
    return CloudLlmProvider.deferred(configId: configId);
  }

  static OpencodeProvider _createOpencodeProvider([String agentId = 'opencode']) {
    final provider = OpencodeProvider(agentId: agentId);
    provider.refreshModelsFromModelsDev();
    return provider;
  }
}
