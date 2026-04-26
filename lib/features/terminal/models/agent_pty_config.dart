import 'package:yoloit/features/terminal/models/agent_type.dart';

/// PTY-based activity detection config per agent type.
///
/// Different CLI agents use different spinner characters and prompt patterns.
/// This config lets each agent type declare its own signals without coupling
/// detection logic to any specific tool.
class AgentPtyConfig {
  const AgentPtyConfig({
    this.spinnerChars = const {},
    this.donePrompts = const {},
    this.approvalPatterns = const {},
    this.idleTimeout = const Duration(seconds: 30),
  });

  /// Characters that appear in PTY output while the agent is actively working
  /// (e.g. spinner frames). Presence of any of these triggers ThinkingPhase.
  final Set<String> spinnerChars;

  /// Substrings in PTY output that signal the agent is done and waiting for
  /// user input (e.g. prompt character). Triggers DonePhase + sound.
  final Set<String> donePrompts;

  /// Substrings in PTY output that signal the agent is waiting for user
  /// approval (e.g. permission dialog). Triggers AwaitingApprovalPhase + sound.
  final Set<String> approvalPatterns;

  /// How long after spinner chars stop before we clear ThinkingPhase.
  final Duration idleTimeout;

  bool get hasDetection =>
      spinnerChars.isNotEmpty ||
      donePrompts.isNotEmpty ||
      approvalPatterns.isNotEmpty;

  /// Returns true if [data] contains any spinner character.
  bool containsSpinner(String data) => spinnerChars.any(data.contains);

  /// Returns true if [data] contains any done-prompt pattern.
  bool containsDonePrompt(String data) => donePrompts.any(data.contains);

  /// Returns true if [data] contains an approval dialog pattern.
  bool containsApproval(String data) => approvalPatterns.any(data.contains);
}

/// Per-agent PTY configs. Extend when adding new agent types.
extension AgentTypePtyConfig on AgentType {
  AgentPtyConfig get ptyConfig {
    switch (this) {
      case AgentType.copilot:
        return const AgentPtyConfig(
          // Copilot spinner cycles through: ○ ◎ ◉ ● (U+25CB, U+25CE, U+25C9, U+25CF)
          // Response bullets use only ● — so we detect the OTHER 3 as spinner-only chars.
          spinnerChars: {
            '\u25CB', // ○ outline circle
            '\u25CE', // ◎ bullseye
            '\u25C9', // ◉ fisheye
          },
          // Copilot shows '› ' as the interactive prompt, but it also renders
          // it in the terminal stream while the agent is still processing,
          // causing false DonePhase flashes. Rely on the idle timeout instead.
          donePrompts: {},
          // Copilot shows these strings when asking user to approve a tool action.
          approvalPatterns: {
            'Do you want to allow',
            'Allow directory access',
            'Allow file access',
            'Allow network access',
            'Enter to confirm',  // bottom hint of ask_user dialogs — more specific than "to confirm"
          },
          // 5s after spinner stops → agent is done responding.
          idleTimeout: Duration(seconds: 5),
        );

      case AgentType.claude:
        return const AgentPtyConfig(
          // Braille spinner frames used by Claude Code CLI.
          spinnerChars: {
            '\u280B', '\u2819', '\u2839', '\u2838',
            '\u283C', '\u2834', '\u2826', '\u2827',
            '\u2807', '\u280F',
          },
          // Claude shows '> ' or similar prompt when idle.
          donePrompts: {'> ', '? '},
        );

      case AgentType.gemini:
        return const AgentPtyConfig(
          // Gemini CLI uses braille spinner (same as Claude).
          spinnerChars: {
            '\u280B', '\u2819', '\u2839', '\u2838',
            '\u283C', '\u2834', '\u2826', '\u2827',
            '\u2807', '\u280F',
          },
          donePrompts: {'> '},
        );

      case AgentType.cursor:
        return const AgentPtyConfig(
          spinnerChars: {'\u25CF', '\u25CB', '\u280B', '\u2819'},
          donePrompts: {'> '},
        );

      case AgentType.pi:
        return const AgentPtyConfig(
          spinnerChars: {'\u25CF', '\u25CB'},
          donePrompts: {'> '},
        );

      case AgentType.terminal:
        // Plain terminal — no automatic activity detection.
        return const AgentPtyConfig();
    }
  }
}
