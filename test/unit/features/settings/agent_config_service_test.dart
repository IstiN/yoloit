import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

void main() {
  test('default Copilot board chat command uses supported flags', () {
    final command = AgentConfigService.defaultBoardChatCommand('copilot');

    expect(command, 'copilot --output-format json');
    expect(command, isNot(contains('--yolo')));
  });
}
