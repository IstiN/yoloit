import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/models/agent_pty_config.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

void main() {
  group('AgentType.ptyConfig', () {
    test('returns a config for every agent type', () {
      for (final type in AgentType.values) {
        expect(type.ptyConfig, isNotNull, reason: type.name);
      }
    });

    test('plain terminal has no activity detection', () {
      final config = AgentType.terminal.ptyConfig;
      expect(config.hasDetection, isFalse);
      expect(config.containsSpinner('⠋'), isFalse);
      expect(config.containsDonePrompt('> '), isFalse);
      expect(config.containsApproval('Do you want to allow'), isFalse);
    });

    test('agent types with detection signals report hasDetection', () {
      for (final type in AgentType.values) {
        if (type == AgentType.terminal) continue;
        expect(type.ptyConfig.hasDetection, isTrue, reason: type.name);
      }
    });

    test('copilot detects spinner circles but not the response bullet', () {
      final config = AgentType.copilot.ptyConfig;
      expect(config.containsSpinner('working ○'), isTrue);
      expect(config.containsSpinner('working ◎'), isTrue);
      expect(config.containsSpinner('working ◉'), isTrue);
      // ● appears in response bullets, so it must not be a spinner char.
      expect(config.containsSpinner('result ●'), isFalse);
      expect(config.containsSpinner('plain text'), isFalse);
    });

    test('copilot detects approval prompts and uses a short idle timeout', () {
      final config = AgentType.copilot.ptyConfig;
      expect(config.containsApproval('Do you want to allow this?'), isTrue);
      expect(config.containsApproval('Allow file access to /tmp?'), isTrue);
      expect(config.containsApproval('Enter to confirm'), isTrue);
      expect(config.containsApproval('all done'), isFalse);
      expect(config.idleTimeout, const Duration(seconds: 5));
      // donePrompts is intentionally empty: '› ' flashes during processing.
      expect(config.containsDonePrompt('› '), isFalse);
    });

    test('claude detects braille spinners and prompt characters', () {
      final config = AgentType.claude.ptyConfig;
      expect(config.containsSpinner('⠋ thinking'), isTrue);
      expect(config.containsSpinner('⠏ done'), isTrue);
      expect(config.containsSpinner('plain'), isFalse);
      expect(config.containsDonePrompt('> '), isTrue);
      expect(config.containsDonePrompt('? '), isTrue);
      expect(config.containsDonePrompt('working…'), isFalse);
      expect(config.idleTimeout, const Duration(seconds: 30));
    });

    test('gemini detects braille spinners and the > prompt', () {
      final config = AgentType.gemini.ptyConfig;
      expect(config.containsSpinner('⠸ working'), isTrue);
      expect(config.containsDonePrompt('> '), isTrue);
      expect(config.containsDonePrompt('? '), isFalse);
    });

    test('cursor detects circle and braille spinners', () {
      final config = AgentType.cursor.ptyConfig;
      expect(config.containsSpinner('●'), isTrue);
      expect(config.containsSpinner('○'), isTrue);
      expect(config.containsSpinner('⠋'), isTrue);
      expect(config.containsDonePrompt('> '), isTrue);
    });

    test('pi detects circle spinners and the > prompt', () {
      final config = AgentType.pi.ptyConfig;
      expect(config.containsSpinner('●'), isTrue);
      expect(config.containsSpinner('○'), isTrue);
      expect(config.containsSpinner('⠋'), isFalse);
      expect(config.containsDonePrompt('> '), isTrue);
    });
  });
}
