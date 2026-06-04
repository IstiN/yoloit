import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/string_utils.dart';

void main() {
  group('truncatePromptText', () {
    test('returns trimmed text when under maxChars', () {
      expect(truncatePromptText('hello world', 20), 'hello world');
    });

    test('collapses whitespace', () {
      expect(
        truncatePromptText('hello   world\t\nfoo', 100),
        'hello world foo',
      );
    });

    test('truncates with ellipsis when over maxChars', () {
      expect(truncatePromptText('hello world', 5), 'hello…');
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

    test('truncates long JSON', () {
      expect(
        compactPromptJson({'key': 'value'}, 5),
        '{"key…',
      );
    });

    test('falls back to toString on non-JSON-serializable value', () {
      expect(
        compactPromptJson(Object(), 10),
        'Instance o…',
      );
    });

    test('handles null', () {
      expect(compactPromptJson(null, 10), 'null');
    });
  });
}
