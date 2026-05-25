import 'package:equatable/equatable.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';

abstract class TerminalState extends Equatable {
  const TerminalState();

  @override
  List<Object?> get props => [];
}

class TerminalInitial extends TerminalState {
  const TerminalInitial();
}

class TerminalLoaded extends TerminalState {
  const TerminalLoaded({
    required this.sessions,
    required this.activeIndex,
    this.allSessions = const [],
    this.requestOpenPanel = false,
  });

  /// Sessions visible in current workspace.
  final List<AgentSession> sessions;
  final int activeIndex;
  /// All sessions across all workspaces — used by the sidebar active-sessions panel.
  final List<AgentSession> allSessions;
  /// When true, the agents panel should be made visible (e.g. after agent:run).
  /// Intentionally excluded from [props] so it never blocks state equality.
  final bool requestOpenPanel;

  AgentSession? get activeSession =>
      sessions.isEmpty ? null : sessions[activeIndex.clamp(0, sessions.length - 1)];

  TerminalLoaded copyWith({
    List<AgentSession>? sessions,
    int? activeIndex,
    List<AgentSession>? allSessions,
    bool requestOpenPanel = false,
  }) {
    return TerminalLoaded(
      sessions: sessions ?? this.sessions,
      activeIndex: activeIndex ?? this.activeIndex,
      allSessions: allSessions ?? this.allSessions,
      requestOpenPanel: requestOpenPanel,
    );
  }

  @override
  List<Object?> get props => [sessions, activeIndex, allSessions];
}
