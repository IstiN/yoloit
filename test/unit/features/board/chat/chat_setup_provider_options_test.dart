import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

void main() {
  group('chat setup provider options', () {
    test('deduplicates visible stream providers by id', () {
      final providers = buildChatProviderOptions([
        const AgentConfig(
          id: 'copilot',
          displayName: 'Copilot old',
          iconLabel: 'CP',
          launchCommand: 'copilot',
          visible: true,
          isBuiltIn: true,
          streamAdapter: 'copilot',
        ),
        const AgentConfig(
          id: 'copilot',
          displayName: 'Copilot',
          iconLabel: 'CP',
          launchCommand: 'copilot',
          visible: true,
          isBuiltIn: true,
          streamAdapter: 'copilot',
        ),
        const AgentConfig(
          id: 'hidden',
          displayName: 'Hidden',
          iconLabel: 'H',
          launchCommand: 'hidden',
          visible: false,
          isBuiltIn: false,
          streamAdapter: 'copilot',
        ),
        const AgentConfig(
          id: 'no-stream',
          displayName: 'No stream',
          iconLabel: 'N',
          launchCommand: 'noop',
          visible: true,
          isBuiltIn: false,
        ),
      ]);

      expect(providers.where((p) => p.$1 == 'copilot'), hasLength(1));
      expect(providers, contains(('copilot', 'Copilot')));
      expect(providers.map((p) => p.$1), isNot(contains('hidden')));
      expect(providers.map((p) => p.$1), isNot(contains('no-stream')));
      expect(providers.map((p) => p.$1), isNot(contains('local')));
    });

    test('falls back to first available provider for stale selection', () {
      final providers = buildChatProviderOptions([
        const AgentConfig(
          id: 'codex',
          displayName: 'Codex',
          iconLabel: 'CX',
          launchCommand: 'codex',
          visible: true,
          isBuiltIn: true,
          streamAdapter: 'codex',
        ),
      ]);

      expect(resolveChatProviderSelection('missing', providers), 'codex');
      expect(resolveChatProviderSelection('codex', providers), 'codex');
    });
  });
}
