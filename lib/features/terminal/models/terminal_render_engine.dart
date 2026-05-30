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
    TerminalRenderEngine.xterm => 'Current renderer, stable baseline.',
    TerminalRenderEngine.kterm => 'Experimental newer renderer for comparison.',
  };

  static TerminalRenderEngine fromId(String? id) {
    return switch (id) {
      'kterm' => TerminalRenderEngine.kterm,
      _ => TerminalRenderEngine.xterm,
    };
  }
}
