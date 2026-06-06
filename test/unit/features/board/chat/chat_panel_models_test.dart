import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

void main() {
  group('ChatSlashCommand', () {
    test('matches when text starts with a trigger', () {
      const cmd = ChatSlashCommand(
        id: 'test',
        displayName: 'Test',
        description: 'D',
        triggers: <String>['/t', '/test'],
      );
      expect(cmd.matches('/test hello'), isTrue);
      expect(cmd.matches('/t'), isTrue);
      expect(cmd.matches('/other'), isFalse);
    });
  });

  group('buildChatProviderOptions', () {
    test('includes visible configs with stream adapter', () {
      final configs = <AgentConfig>[
        const AgentConfig(
          id: 'openai',
          displayName: 'OpenAI',
          iconLabel: 'O',
          launchCommand: '',
          visible: true,
          isBuiltIn: true,
          streamAdapter: 'openai',
        ),
        const AgentConfig(
          id: 'hidden',
          displayName: 'Hidden',
          iconLabel: 'H',
          launchCommand: '',
          visible: false,
          isBuiltIn: true,
          streamAdapter: 'x',
        ),
        const AgentConfig(
          id: 'nostream',
          displayName: 'No Stream',
          iconLabel: 'N',
          launchCommand: '',
          visible: true,
          isBuiltIn: true,
        ),
      ];
      final options = buildChatProviderOptions(configs);
      expect(
        options.map((e) => e.$1).toList(),
        containsAll(<String>['openai', 'local']),
      );
      expect(options.map((e) => e.$1).toList(), isNot(contains('hidden')));
      expect(options.map((e) => e.$1).toList(), isNot(contains('nostream')));
    });

    test('always includes local fallback', () {
      final options = buildChatProviderOptions(<AgentConfig>[]);
      expect(options.single.$1, 'local');
    });
  });

  group('resolveChatProviderSelection', () {
    test('returns selection when it exists', () {
      final providers = <(String, String)>[('a', 'A'), ('b', 'B')];
      expect(resolveChatProviderSelection('b', providers), 'b');
    });

    test('falls back to first provider', () {
      final providers = <(String, String)>[('a', 'A'), ('b', 'B')];
      expect(resolveChatProviderSelection('c', providers), 'a');
    });

    test('returns null for empty providers', () {
      expect(resolveChatProviderSelection('a', <(String, String)>[]), isNull);
    });
  });

  group('extractExitCode', () {
    test('extracts exit code phrase', () {
      expect(extractExitCode('exited with exit code 42'), 42);
      expect(extractExitCode('Exit code 7'), 7);
    });

    test('returns null when absent', () {
      expect(extractExitCode('some output'), isNull);
    });
  });

  group('toolResultPreview', () {
    test('returns first non-empty line without exit code phrase', () {
      expect(
        toolResultPreview('line1\nline2\nexited with exit code 0'),
        'line1',
      );
    });

    test('strips HTML tags', () {
      expect(
        toolResultPreview('<div>content</div>'),
        'content',
      );
    });

    test('returns exit code summary when no other content', () {
      expect(
        toolResultPreview('exited with exit code 5'),
        'Exited with code 5',
      );
    });

    test('returns null when completely empty', () {
      expect(toolResultPreview('   \n   '), isNull);
    });
  });

  group('SubAgentEvent and SubAgentRunState', () {
    test('event holds fields', () {
      final event = SubAgentEvent(
        type: 'tool_start',
        timestamp: DateTime(2024),
        toolName: 't',
        content: 'c',
      );
      expect(event.type, 'tool_start');
      expect(event.toolName, 't');
      expect(event.content, 'c');
    });

    test('run state initializes', () {
      final state = SubAgentRunState(
        agentId: 'a',
        agentName: 'n',
        agentDescription: 'd',
      );
      expect(state.agentId, 'a');
      expect(state.isRunning, isTrue);
      expect(state.events, isEmpty);
    });
  });
}
