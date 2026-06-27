import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

void main() {
  test('openAiToolDefinitions uses compact aliases and param keys', () {
    final compact = YoloitCliToolCatalog.openAiToolDefinitions(compact: true);
    final sticky = compact.firstWhere(
      (tool) =>
          ((tool['function'] as Map<String, Object?>)['name'] as String?) ==
          'sta',
    );
    final fn = sticky['function']! as Map<String, Object?>;
    expect(fn['description'], 'Append text to a sticky note');
    expect(fn['description'], isNot(contains('yoloit sticky:append')));

    final params = fn['parameters']! as Map<String, Object?>;
    final props = params['properties']! as Map<String, Object?>;
    final textProp = props['tx']! as Map<String, Object?>;
    expect(textProp['type'], 'string');
    expect(textProp.containsKey('description'), isFalse);
  });

  test('openAiToolDefinitions full mode keeps verbose schema', () {
    final full = YoloitCliToolCatalog.openAiToolDefinitions(compact: false);
    final sticky = full.firstWhere(
      (tool) =>
          ((tool['function'] as Map<String, Object?>)['name'] as String?) ==
          'yoloit_sticky_append',
    );
    final fn = sticky['function']! as Map<String, Object?>;
    expect(fn['description'], contains('yoloit sticky:append'));

    final params = fn['parameters']! as Map<String, Object?>;
    final props = params['properties']! as Map<String, Object?>;
    final textProp = props['text']! as Map<String, Object?>;
    expect(textProp.containsKey('description'), isTrue);
  });
}
