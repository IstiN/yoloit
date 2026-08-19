/// Fuzzy file name matcher with Russian keyboard layout transliteration.
///
/// Supports:
///   - Exact substring matching (highest priority)
///   - Subsequence matching: "PR" matches "PropertyReader"
///   - Russian → English transliteration: "ЗкщзукенКуфвук" → "PropertyReader"
class FuzzyMatcher {
  FuzzyMatcher._();

  /// Maps each Russian character to the Latin character on the same physical key
  /// of a standard QWERTY keyboard with Russian (ЙЦУКЕН) layout.
  static const _rusToEng = <String, String>{
    'й': 'q', 'ц': 'w', 'у': 'e', 'к': 'r', 'е': 't', 'н': 'y',
    'г': 'u', 'ш': 'i', 'щ': 'o', 'з': 'p', 'х': '[', 'ъ': ']',
    'ф': 'a', 'ы': 's', 'в': 'd', 'а': 'f', 'п': 'g', 'р': 'h',
    'о': 'j', 'л': 'k', 'д': 'l', 'ж': ';', 'э': "'",
    'я': 'z', 'ч': 'x', 'с': 'c', 'м': 'v', 'и': 'b', 'т': 'n',
    'ь': 'm', 'б': ',', 'ю': '.',
    // Uppercase
    'Й': 'Q', 'Ц': 'W', 'У': 'E', 'К': 'R', 'Е': 'T', 'Н': 'Y',
    'Г': 'U', 'Ш': 'I', 'Щ': 'O', 'З': 'P', 'Х': '{', 'Ъ': '}',
    'Ф': 'A', 'Ы': 'S', 'В': 'D', 'А': 'F', 'П': 'G', 'Р': 'H',
    'О': 'J', 'Л': 'K', 'Д': 'L', 'Ж': ':', 'Э': '"',
    'Я': 'Z', 'Ч': 'X', 'С': 'C', 'М': 'V', 'И': 'B', 'Т': 'N',
    'Ь': 'M', 'Б': '<', 'Ю': '>',
  };

  static final Map<String, String> _engToRus = {
    for (final entry in _rusToEng.entries) entry.value: entry.key,
  };

  /// Converts a string typed with a Russian keyboard layout to its Latin equivalent.
  /// e.g. "ЗкщзукенКуфвук" → "PropertyReader"
  static String transliterateRu(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(_rusToEng[c] ?? c);
    }
    return buffer.toString();
  }

  /// Converts a string typed with an English keyboard layout to its Russian
  /// equivalent. e.g. "ghbdtn" → "привет".
  static String transliterateEng(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(_engToRus[c] ?? c);
    }
    return buffer.toString();
  }

  /// Returns true if the string contains any Cyrillic characters.
  static bool isCyrillic(String text) =>
      text.runes.any((r) => (r >= 0x0400 && r <= 0x04FF));

  /// Returns true if the string contains Latin characters.
  static bool isLatin(String text) => text.runes.any(
    (r) => (r >= 0x0041 && r <= 0x005A) || (r >= 0x0061 && r <= 0x007A),
  );

  /// Returns all candidate queries to try for the given user input.
  /// If the input is Cyrillic the transliterated version is added automatically.
  static List<String> candidates(String query) {
    final candidates = [query];
    if (isCyrillic(query)) {
      final eng = transliterateRu(query);
      if (eng != query) candidates.add(eng);
    }
    if (isLatin(query)) {
      final rus = transliterateEng(query);
      if (rus != query) candidates.add(rus);
    }
    return candidates;
  }

  /// Scores [text] against [query] (case-insensitive).
  /// Higher score = better match. Returns null when there is no match at all.
  ///
  /// Priority tiers:
  ///   10000 — exact match
  ///    5000 — text starts with query  (filename prefix)
  ///    3000 — text contains query     (substring)
  ///    1000 — subsequence match       (e.g. "PR" in "PropertyReader")
  ///
  /// Within each tier a **density bonus** (0–1000) is added:
  ///   densityBonus = round(queryLen / textLen × 1000)
  ///
  /// This ensures that shorter filenames where the query fills a larger
  /// proportion of the name rank above longer filenames with the same
  /// base match type. e.g.:
  ///   "PropertyReader.java"  (density 9/18 = 0.50 → +500)
  ///   "PropertyReaderTest.java" (9/22 = 0.41 → +409)
  ///   "PropertyReaderConfluenceAuthTest.java" (9/36 = 0.25 → +250)
  static int? score(String text, String query) {
    if (query.isEmpty) return null;
    // Skip re-lowercasing when callers already pass lowercase (quick-open
    // and file search pre-normalize); toLowerCase allocates on every call
    // and this runs once per candidate file per keystroke.
    final t = _isLowerCase(text) ? text : text.toLowerCase();
    final q = _isLowerCase(query) ? query : query.toLowerCase();

    // Density: fraction of the filename covered by the query (0–1000 bonus).
    final densityBonus = (q.length / t.length * 1000).round().clamp(0, 1000);

    if (t == q) return 10000;
    if (t.startsWith(q)) return 5000 + densityBonus;
    final idx = t.indexOf(q);
    if (idx >= 0) return 3000 + densityBonus;
    final subScore = _subsequenceScore(t, q);
    if (subScore != null) return 1000 + densityBonus + subScore;
    return null;
  }

  static bool _isLowerCase(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) return false; // A-Z
      if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return false; // À-Þ
    }
    return true;
  }

  /// Best score across all [queries]. Returns null when nothing matches.
  static int? bestScore(String text, List<String> queries) {
    int? best;
    for (final q in queries) {
      final s = score(text, q);
      if (s != null && (best == null || s > best)) best = s;
    }
    return best;
  }

  /// Returns indices in [text] that form the subsequence match for [query].
  /// Used for per-character highlight rendering.
  /// Returns an empty list when there is no match.
  static List<int> matchIndices(String text, String query) {
    if (query.isEmpty) return [];
    final t = text.toLowerCase();
    final q = query.toLowerCase();

    // Prefer highlighting a contiguous substring first
    final idx = t.indexOf(q);
    if (idx >= 0) {
      return List.generate(q.length, (i) => idx + i);
    }

    // Fall back to subsequence positions
    final indices = <int>[];
    int qi = 0;
    for (int i = 0; i < t.length && qi < q.length; i++) {
      if (t[i] == q[qi]) {
        indices.add(i);
        qi++;
      }
    }
    return qi == q.length ? indices : [];
  }

  /// Like [matchIndices] but tries all [queries] and returns the best (most
  /// contiguous) set of indices.
  static List<int> bestMatchIndices(String text, List<String> queries) {
    List<int> best = [];
    for (final q in queries) {
      final indices = matchIndices(text, q);
      if (indices.isEmpty) continue;
      // Prefer more contiguous matches (smaller span)
      if (best.isEmpty ||
          (indices.last - indices.first) < (best.last - best.first)) {
        best = indices;
      }
    }
    return best;
  }

  // ---- private helpers -------------------------------------------------------

  /// Returns a consecutive-run bonus for subsequence matches.
  /// Each pair of adjacent matched characters adds +10.
  /// This does NOT use position values, so scores are comparable across
  /// filenames of different lengths.
  static int? _subsequenceScore(String text, String query) {
    int qi = 0;
    int consecutiveBonus = 0;
    int lastI = -1;
    for (int i = 0; i < text.length && qi < query.length; i++) {
      if (text[i] == query[qi]) {
        if (lastI >= 0 && i == lastI + 1) consecutiveBonus += 10;
        lastI = i;
        qi++;
      }
    }
    return qi == query.length ? consecutiveBonus : null;
  }
}
