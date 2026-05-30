enum TerminalBackendMode { local, runtime, tmux }

extension TerminalBackendModeX on TerminalBackendMode {
  String get id => switch (this) {
    TerminalBackendMode.local => 'local',
    TerminalBackendMode.runtime => 'runtime',
    TerminalBackendMode.tmux => 'tmux',
  };

  String get label => switch (this) {
    TerminalBackendMode.local => 'Local PTY',
    TerminalBackendMode.runtime => 'YoLoIT Runtime',
    TerminalBackendMode.tmux => 'tmux',
  };

  String get description => switch (this) {
    TerminalBackendMode.local => 'Best scroll UX; sessions stop with the app.',
    TerminalBackendMode.runtime =>
      'Default YoLoIT-owned persistent session host.',
    TerminalBackendMode.tmux =>
      'Legacy persistent backend; may intercept scroll.',
  };

  static TerminalBackendMode fromId(String? id) {
    return switch (id) {
      'local' => TerminalBackendMode.local,
      'runtime' => TerminalBackendMode.runtime,
      'tmux' => TerminalBackendMode.tmux,
      _ => TerminalBackendMode.runtime,
    };
  }
}
