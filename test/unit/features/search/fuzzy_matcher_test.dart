import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';

void main() {
  group('FuzzyMatcher.transliterateRu', () {
    test('converts Russian ЙЦУКЕН layout to English', () {
      // "PropertyReader" typed on Russian keyboard
      expect(FuzzyMatcher.transliterateRu('ЗкщзукенКуфвук'), 'PropertyReader');
    });

    test('preserves Latin characters', () {
      expect(FuzzyMatcher.transliterateRu('hello'), 'hello');
    });

    test('handles mixed input', () {
      // 'з' → 'p', 'у' → 'e', 'н' → 'y'  (н is on the 'y' key, not 'n')
      expect(FuzzyMatcher.transliterateRu('зун'), 'pey');
    });

    test('converts uppercase Russian correctly', () {
      // З → P, К → R
      expect(FuzzyMatcher.transliterateRu('ЗК'), 'PR');
    });
  });

  group('FuzzyMatcher.transliterateEng', () {
    test('converts English QWERTY layout to Russian', () {
      expect(FuzzyMatcher.transliterateEng('ghbdtn'), 'привет');
    });

    test('preserves Cyrillic characters', () {
      expect(FuzzyMatcher.transliterateEng('привет'), 'привет');
    });
  });

  group('FuzzyMatcher.isCyrillic', () {
    test('returns true for Russian text', () {
      expect(FuzzyMatcher.isCyrillic('Привет'), isTrue);
    });

    test('returns false for Latin text', () {
      expect(FuzzyMatcher.isCyrillic('hello'), isFalse);
    });

    test('returns true for mixed text with at least one Cyrillic char', () {
      expect(FuzzyMatcher.isCyrillic('helloМир'), isTrue);
    });
  });

  group('FuzzyMatcher.candidates', () {
    test('returns original + Russian layout candidate for Latin input', () {
      final result = FuzzyMatcher.candidates('hello');
      expect(result, ['hello', 'руддщ']);
    });

    test('returns original + transliterated for Cyrillic input', () {
      final result = FuzzyMatcher.candidates('ЗкщзукенКуфвук');
      expect(result.length, 2);
      expect(result[0], 'ЗкщзукенКуфвук');
      expect(result[1], 'PropertyReader');
    });

    test('maps mistyped Russian text from Latin layout', () {
      final result = FuzzyMatcher.candidates('ghbdtn');
      expect(result, containsAllInOrder(['ghbdtn', 'привет']));
    });
  });

  group('FuzzyMatcher.score', () {
    test('exact match returns 10000', () {
      expect(FuzzyMatcher.score('main.dart', 'main.dart'), 10000);
    });

    test('prefix match returns >= 5000', () {
      final s = FuzzyMatcher.score('main_shell.dart', 'main');
      expect(s, isNotNull);
      expect(s!, greaterThanOrEqualTo(5000));
      expect(s, lessThan(10000));
    });

    test('substring match returns >= 3000', () {
      final s = FuzzyMatcher.score('file_editor_cubit.dart', 'editor');
      expect(s, isNotNull);
      expect(s!, greaterThanOrEqualTo(3000));
      expect(s, lessThan(5000));
    });

    test('subsequence match returns >= 1000', () {
      // "FC" in "FileSearchCubit" — F=0, C=10 — not a prefix ("fi" ≠ "fc")
      // and not a substring, so it's a pure subsequence match
      final s = FuzzyMatcher.score('FileSearchCubit.dart', 'FC');
      expect(s, isNotNull);
      expect(s!, greaterThanOrEqualTo(1000));
    });

    test('no match returns null', () {
      expect(FuzzyMatcher.score('main.dart', 'xyz'), isNull);
    });

    test('case insensitive matching', () {
      expect(FuzzyMatcher.score('MainShell.dart', 'mainshell'), isNotNull);
    });

    test('empty query returns null', () {
      expect(FuzzyMatcher.score('main.dart', ''), isNull);
    });

    test('prefix match scores higher than substring', () {
      // "PropertyReader.java" starts with "Prop" → prefix match
      // "MyPropertyReader.java" contains "Prop" → substring match
      final prefix = FuzzyMatcher.score('PropertyReader.java', 'Prop');
      final substring = FuzzyMatcher.score('MyPropertyReader.java', 'Prop');
      expect(prefix!, greaterThan(substring!));
    });

    test('shorter filename ranks higher than longer with same query', () {
      // Both start with "PropertyReader" → both prefix matches.
      // Shorter file should win via higher density bonus.
      final shorter = FuzzyMatcher.score(
        'PropertyReader.java',
        'PropertyReader',
      );
      final longer = FuzzyMatcher.score(
        'PropertyReaderConfluenceAuthTest.java',
        'PropertyReader',
      );
      expect(shorter!, greaterThan(longer!));
    });

    test('density bonus: query filling 50% ranks above 25%', () {
      // 9-char query in 18-char file vs 36-char file
      final dense = FuzzyMatcher.score(
        'ProReader.java',
        'ProReader',
      ); // exact match
      final sparse = FuzzyMatcher.score(
        'ProReaderConfluenceTest.java',
        'ProReader',
      );
      expect(dense!, greaterThan(sparse!));
    });
  });

  group('FuzzyMatcher.bestScore', () {
    test('returns best score across queries', () {
      final queries = FuzzyMatcher.candidates('ЗкщзукенКуфвук');
      final s = FuzzyMatcher.bestScore('PropertyReader.dart', queries);
      expect(s, isNotNull);
      expect(s!, greaterThanOrEqualTo(1000));
    });

    test('matches Russian text when typed in English layout', () {
      final queries = FuzzyMatcher.candidates('ghbdtn');
      final s = FuzzyMatcher.bestScore('привет мир', queries);
      expect(s, isNotNull);
    });

    test('returns null when no query matches', () {
      expect(FuzzyMatcher.bestScore('main.dart', ['xyz', 'abc']), isNull);
    });
  });

  group('FuzzyMatcher.matchIndices', () {
    test('returns contiguous indices for substring match', () {
      final indices = FuzzyMatcher.matchIndices('PropertyReader', 'ader');
      expect(indices, [10, 11, 12, 13]);
    });

    test('returns subsequence indices for non-contiguous match', () {
      // "PR" in "PropertyReader": P=0, R=8
      final indices = FuzzyMatcher.matchIndices('PropertyReader', 'PR');
      expect(indices, isNotEmpty);
      expect(indices[0], 0); // 'P'
      // 'R' should appear somewhere after 'P'
      expect(indices[1], greaterThan(0));
    });

    test('returns empty list when no match', () {
      expect(FuzzyMatcher.matchIndices('main.dart', 'xyz'), isEmpty);
    });

    test('case insensitive', () {
      expect(FuzzyMatcher.matchIndices('MAIN.dart', 'main'), [0, 1, 2, 3]);
    });
  });

  group('FuzzyMatcher.bestMatchIndices', () {
    test('finds PropertyReader via Russian transliteration', () {
      final queries = FuzzyMatcher.candidates('ЗкщзукенКуфвук');
      // transliterates to "PropertyReader", which is a full substring of the filename
      final indices = FuzzyMatcher.bestMatchIndices(
        'PropertyReader.dart',
        queries,
      );
      expect(indices, isNotEmpty);
      // "PropertyReader" is 14 chars → 14 highlighted indices
      expect(indices.length, 14);
    });

    test('prefers more contiguous match', () {
      // Both 'abc' and 'a..b..c' match — should prefer tighter span
      final indices = FuzzyMatcher.bestMatchIndices('abcdef', ['abc']);
      expect(indices, [0, 1, 2]);
    });

    test('returns empty for no match', () {
      expect(FuzzyMatcher.bestMatchIndices('main.dart', ['xyz']), isEmpty);
    });
  });
}
