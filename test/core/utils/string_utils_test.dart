import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/string_utils.dart';

void main() {
  group('truncatePromptText', () {
    test('returns trimmed text', () {
      expect(truncatePromptText('hello world', 20), 'hello world');
    });

    test('collapses whitespace', () {
      expect(
        truncatePromptText('hello   world\t\nfoo', 100),
        'hello world foo',
      );
    });

    test('does not truncate long text', () {
      expect(
        truncatePromptText('hello world', 5),
        'hello world',
      );
    });

    test('handles empty string', () {
      expect(truncatePromptText('', 10), '');
    });
  });

  group('compactPromptJson', () {
    test('returns compact JSON for map', () {
      expect(
        compactPromptJson({'key': 'value'}, 100),
        '{"key":"value"}',
      );
    });

    test('does not truncate long JSON', () {
      expect(
        compactPromptJson({'key': 'value'}, 5),
        '{"key":"value"}',
      );
    });

    test('falls back to toString on non-JSON-serializable value', () {
      expect(
        compactPromptJson(Object(), 10),
        startsWith('Instance of'),
      );
    });

    test('handles null', () {
      expect(compactPromptJson(null, 10), 'null');
    });
  });
}
