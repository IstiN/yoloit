import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_core.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Shared session-map logic for VM and web [ChatSessionManager]s.
///
/// Mix this into a class that declares:
///   - `Map<String, ChatSession> get sessions`
///   - `ChatProvider Function(String providerId)? get providerFactory`
mixin ChatSessionManagerMixin {
  Map<String, ChatSession> get sessions;
  ChatProvider Function(String providerId)? get providerFactory;

  /// Get an existing session or create a new one.
  ///
  /// If a session for [panelId] already exists, returns it (potentially
  /// updating config if [config] differs). If not, creates a new one.
  ChatSession getOrCreate(
    String panelId,
    ChatSessionConfig config,
  ) {
    final existing = sessions[panelId];
    if (existing != null) {
      existing.updateConfig(config);
      return existing;
    }
    final session = ChatSession(
      panelId: panelId,
      config: config,
      providerFactory: providerFactory,
    );
    sessions[panelId] = session;
    return session;
  }

  /// Get a session by panel ID, or null if it doesn't exist.
  ChatSession? get(String panelId) => sessions[panelId];

  /// Check if a session exists.
  bool has(String panelId) => sessions.containsKey(panelId);

  /// Remove and dispose a session (kills processes).
  void remove(String panelId) {
    final session = sessions.remove(panelId);
    session?.dispose();
  }

  /// Detach a session (UI going away, but keep session alive).
  void detach(String panelId) {
    sessions[panelId]?.detach();
  }

  /// List all active session panel IDs.
  List<String> get activeSessionIds => sessions.keys.toList();

  /// Dispose all sessions. Called on app shutdown.
  void disposeAll() {
    for (final session in sessions.values) {
      session.dispose();
    }
    sessions.clear();
  }
}
