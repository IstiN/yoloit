enum TerminalRenderEngine { xterm }

extension TerminalRenderEngineX on TerminalRenderEngine {
  String get id => 'xterm';

  String get label => 'xterm.dart';

  String get description => 'Default renderer.';

  static TerminalRenderEngine fromId(String? id) => TerminalRenderEngine.xterm;
}
