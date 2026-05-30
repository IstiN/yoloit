enum TerminalRenderEngine { xterm, kterm }

extension TerminalRenderEngineX on TerminalRenderEngine {
  String get id => switch (this) {
    TerminalRenderEngine.xterm => 'xterm',
    TerminalRenderEngine.kterm => 'kterm',
  };

  String get label => switch (this) {
    TerminalRenderEngine.xterm => 'xterm.dart',
    TerminalRenderEngine.kterm => 'kterm',
  };

  String get description => switch (this) {
    TerminalRenderEngine.xterm => 'Legacy stable baseline.',
    TerminalRenderEngine.kterm => 'Default newer renderer.',
  };

  static TerminalRenderEngine fromId(String? id) {
    return switch (id) {
      'xterm' => TerminalRenderEngine.xterm,
      'kterm' => TerminalRenderEngine.kterm,
      _ => TerminalRenderEngine.kterm,
    };
  }
}
