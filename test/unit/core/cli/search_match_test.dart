// Tests for the search fuzzy-matching logic extracted from CliServer.
// Mirrors the _matchSnippet / _buildSnippet behaviour so we can verify
// edge cases without spinning up a full server.

import 'package:flutter_test/flutter_test.dart';

// Standalone port of the matching logic (kept in sync with cli_server.dart).
String? matchSnippet(String text, String query) {
  final haystack = text.toLowerCase();
  final needle = query.toLowerCase().trim();

  final exactIdx = haystack.indexOf(needle);
  if (exactIdx >= 0) return _buildSnippet(text, exactIdx, needle.length);

  final normHaystack = haystack.replaceAll(RegExp(r'[_\-.]'), ' ');
  final normNeedle = needle.replaceAll(RegExp(r'[_\-.]'), ' ');

  final normIdx = normHaystack.indexOf(normNeedle);
  if (normIdx >= 0) return _buildSnippet(text, normIdx, normNeedle.length);

  final queryWords =
      normNeedle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (queryWords.length > 1) {
    final allMatch = queryWords.every((w) => normHaystack.contains(w));
    if (allMatch) {
      final firstIdx = normHaystack.indexOf(queryWords.first);
      return _buildSnippet(
        text,
        firstIdx < 0 ? 0 : firstIdx,
        queryWords.first.length,
      );
    }
  }
  return null;
}

String _buildSnippet(String text, int matchIdx, int matchLen) {
  final start = (matchIdx - 48).clamp(0, text.length);
  final end = (matchIdx + matchLen + 72).clamp(0, text.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end).replaceAll('\n', ' ')}$suffix';
}

void main() {
  group('search matchSnippet', () {
    test('exact substring match (case-insensitive)', () {
      expect(matchSnippet('Demo Copilot Chat', 'copilot'), isNotNull);
      expect(matchSnippet('Demo Copilot Chat', 'COPILOT'), isNotNull);
    });

    test('space query matches underscore title', () {
      expect(matchSnippet('demo_copilot', 'demo copilot'), isNotNull);
    });

    test('underscore query matches underscore title', () {
      expect(matchSnippet('demo_copilot', 'demo_copilot'), isNotNull);
    });

    test('space query matches hyphen title', () {
      expect(matchSnippet('demo-copilot', 'demo copilot'), isNotNull);
    });

    test('word-order-independent match: "copilot demo" matches "Demo Copilot"', () {
      expect(matchSnippet('Demo Copilot Chat', 'copilot demo'), isNotNull);
    });

    test('"demo copilot" matches panel id demo_copilot', () {
      expect(matchSnippet('demo_copilot', 'demo copilot'), isNotNull);
    });

    test('"copilot demo chat" matches "Demo Copilot Chat"', () {
      expect(matchSnippet('Demo Copilot Chat', 'copilot demo chat'), isNotNull);
    });

    test('unrelated query returns null', () {
      expect(matchSnippet('Demo Copilot Chat', 'kanban board'), isNull);
    });

    test('partial word match inside longer text', () {
      expect(matchSnippet('This is a demo_copilot panel', 'demo copilot'), isNotNull);
    });
  });
}
