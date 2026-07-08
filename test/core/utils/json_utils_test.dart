import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/json_utils.dart';

void main() {
  group('panelSummaryFromStdout', () {
    test('returns null for null', () {
      expect(panelSummaryFromStdout(null), isNull);
    });

    test('returns null for empty string', () {
      expect(panelSummaryFromStdout(''), isNull);
    });

    test('returns null for non-JSON string', () {
      expect(panelSummaryFromStdout('not json'), isNull);
    });

    test('returns null for JSON without panel', () {
      expect(panelSummaryFromStdout('{"foo":"bar"}'), isNull);
    });

    test('extracts id, title, type from panel', () {
      final result = panelSummaryFromStdout(
        '{"panel":{"id":"p1","title":"T","type":"note"}}',
      );
      expect(result, {'id': 'p1', 'title': 'T', 'type': 'note'});
    });

    test('omits missing fields', () {
      final result = panelSummaryFromStdout('{"panel":{"id":"p1"}}');
      expect(result, {'id': 'p1'});
    });
  });

  group('compactToolResultForPrompt', () {
    test('returns none for null', () {
      expect(compactToolResultForPrompt(null), 'none');
    });

    test('returns none for empty string', () {
      expect(compactToolResultForPrompt(''), 'none');
    });

    test('returns full raw text for non-JSON', () {
      final longText = 'a' * 1000;
      expect(
        compactToolResultForPrompt(longText),
        longText,
      );
    });

    test('compacts JSON with ok, command, error', () {
      final result = compactToolResultForPrompt(
        '{"ok":true,"command":"ls","error":null,"extra":"ignored"}',
      );
      expect(result, contains('"ok":true'));
      expect(result, contains('"command":"ls"'));
      expect(result, isNot(contains('extra')));
    });

    test('includes panel summary when stdout has panel', () {
      final result = compactToolResultForPrompt(
        '{"ok":true,"stdout":"{\\"panel\\":{\\"id\\":\\"p1\\",\\"title\\":\\"T\\"}}"}',
      );
      expect(result, contains('"ok":true'));
      expect(result, contains('"panel"'));
      expect(result, contains('"id":"p1"'));
    });

    test('does not truncate compact JSON', () {
      final longValue = 'x' * 2000;
      final result = compactToolResultForPrompt(
        '{"ok":true,"command":"$longValue"}',
      );
      expect(result, contains(longValue));
    });
  });
}
