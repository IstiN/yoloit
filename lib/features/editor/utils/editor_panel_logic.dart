/// Pure text-manipulation and parsing helpers for the file editor panel.
///
/// Extracted from `file_editor_panel.dart` so the logic can be unit-tested
/// without pumping widgets. All functions are side-effect free (except the
/// bounded outline-symbol cache) and behave exactly like the original
/// private helpers they replace.
library;

// ── Git gutter ───────────────────────────────────────────────────────────────

/// Git gutter marker kinds parsed from unified diff output.
enum GutterMarkerType { added, removed }

/// Parses unified diff output into a line-number → marker type map.
Map<int, GutterMarkerType> parseDiffMarkers(String diff) {
  final result = <int, GutterMarkerType>{};
  int newLine = 0;

  for (final line in diff.split('\n')) {
    if (line.startsWith('@@')) {
      final match = RegExp(r'\+(\d+)').firstMatch(line);
      if (match != null) newLine = int.parse(match.group(1)!) - 1;
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      newLine++;
      result[newLine] = GutterMarkerType.added;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      // Removed line — mark the next new-file line as a deletion indicator.
      final nextLine = newLine + 1;
      if (!result.containsKey(nextLine)) {
        result[nextLine] = GutterMarkerType.removed;
      }
    } else if (!line.startsWith('\\')) {
      newLine++;
    }
  }
  return result;
}

// ── File type helpers ────────────────────────────────────────────────────────

bool isMarkdownPath(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  return ext == 'md' || ext == 'mdx' || ext == 'markdown';
}

bool isEditorImagePath(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  return const {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'ico',
  }.contains(ext);
}

bool isSvgPath(String filePath) =>
    filePath.split('.').last.toLowerCase() == 'svg';

// ── Large file detection ─────────────────────────────────────────────────────

const int kLargeFileLineThreshold = 3000;
const int kLargeFileByteThreshold = 100 * 1024;

/// True when [content] is too big for eager syntax highlighting.
bool isLargeEditorFile(String? content) {
  if (content == null) return false;
  if (content.length > kLargeFileByteThreshold) return true;
  var lines = 0;
  for (var i = 0; i < content.length; i++) {
    if (content[i] == '\n') lines++;
    if (lines > kLargeFileLineThreshold) return true;
  }
  return false;
}

// ── Outline symbol parsing ───────────────────────────────────────────────────

/// A symbol shown in the editor outline panel.
class OutlineSymbol {
  const OutlineSymbol({
    required this.name,
    required this.line,
    required this.isClass,
  });

  final String name;
  final int line;
  final bool isClass;

  @override
  bool operator ==(Object other) =>
      other is OutlineSymbol &&
      other.name == name &&
      other.line == line &&
      other.isClass == isClass;

  @override
  int get hashCode => Object.hash(name, line, isClass);

  @override
  String toString() => 'OutlineSymbol($name, line: $line, isClass: $isClass)';
}

// Cache key: content length + hash + path → symbols.
// This avoids re-parsing the entire file on every build when the outline
// panel is visible.
final _symbolCache = <String, List<OutlineSymbol>>{};

String _symbolCacheKey(String content, String filePath) {
  return '${content.length}:${content.hashCode}:$filePath';
}

/// Parses the outline symbols for [content] based on the [filePath] extension.
List<OutlineSymbol> parseOutlineSymbols(String content, String filePath) {
  final key = _symbolCacheKey(content, filePath);
  final cached = _symbolCache[key];
  if (cached != null) return cached;

  final ext = filePath.split('.').last.toLowerCase();
  final lines = content.split('\n');
  final symbols = <OutlineSymbol>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    switch (ext) {
      case 'dart':
        parseDartSymbolLine(line, t, i, symbols);
      case 'js' || 'ts' || 'jsx' || 'tsx':
        parseJsSymbolLine(t, i, symbols);
      case 'py':
        parsePySymbolLine(t, i, symbols);
    }
  }

  // Trim cache if it grows too large (leak prevention).
  if (_symbolCache.length > 50) {
    _symbolCache.remove(_symbolCache.keys.first);
  }
  _symbolCache[key] = symbols;
  return symbols;
}

void parseDartSymbolLine(
  String line,
  String t,
  int i,
  List<OutlineSymbol> symbols,
) {
  if (RegExp(
    r'^(abstract\s+)?(?:class|enum|mixin|extension)\s+\w+',
  ).hasMatch(t)) {
    final m = RegExp(r'(?:class|enum|mixin|extension)\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true));
    }
  } else {
    final m = RegExp(
      r'(?:Future(?:<[^>]*>)?|Widget|void|String|int|bool|double|List|Map|dynamic)\s+(\w+)\s*[\(<]',
    ).firstMatch(line);
    if (m != null &&
        !['if', 'for', 'while', 'switch', 'return'].contains(m.group(1))) {
      symbols.add(
        OutlineSymbol(name: '${m.group(1)!}()', line: i + 1, isClass: false),
      );
    }
  }
}

void parseJsSymbolLine(String t, int i, List<OutlineSymbol> symbols) {
  if (t.startsWith('class ')) {
    final m = RegExp(r'class\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true));
    }
  } else if (RegExp(
    r'^(?:export\s+)?(?:async\s+)?function\s+\w+',
  ).hasMatch(t)) {
    final m = RegExp(r'function\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(
        OutlineSymbol(name: '${m.group(1)!}()', line: i + 1, isClass: false),
      );
    }
  } else if (RegExp(
    r'^(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?\(',
  ).hasMatch(t)) {
    final m = RegExp(r'(?:const|let|var)\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(
        OutlineSymbol(name: '${m.group(1)!}()', line: i + 1, isClass: false),
      );
    }
  }
}

void parsePySymbolLine(String t, int i, List<OutlineSymbol> symbols) {
  if (t.startsWith('class ')) {
    final m = RegExp(r'class\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true));
    }
  } else if (t.startsWith('def ') || t.startsWith('async def ')) {
    final m = RegExp(r'def\s+(\w+)').firstMatch(t);
    if (m != null) {
      symbols.add(
        OutlineSymbol(name: '${m.group(1)!}()', line: i + 1, isClass: false),
      );
    }
  }
}

// ── Auto-pairs ───────────────────────────────────────────────────────────────

/// Returns the closing bracket for an opening bracket character, or null.
String? closingBracketFor(String ch) => switch (ch) {
  '(' => ')',
  '[' => ']',
  '{' => '}',
  _ => null,
};

/// Decides whether a single-character insertion should auto-insert a closing
/// bracket. Returns the paired text and the cursor position to keep, or null
/// when no auto-pair applies.
({String text, int cursor})? applyAutoPair({
  required String prevText,
  required String curText,
  required bool selectionCollapsed,
  required int cursorPos,
}) {
  if (!selectionCollapsed) return null;
  if (curText.length != prevText.length + 1) return null;
  if (cursorPos < 1) return null;
  final closing = closingBracketFor(curText[cursorPos - 1]);
  if (closing == null) return null;

  // Don't double-close when next char is already the closer.
  final nextCh = cursorPos < curText.length ? curText[cursorPos] : '';
  if (nextCh == closing) return null;

  return (
    text:
        curText.substring(0, cursorPos) +
        closing +
        curText.substring(cursorPos),
    cursor: cursorPos,
  );
}

// ── Line helpers ─────────────────────────────────────────────────────────────

/// Returns the [start, end) range of the line containing [pos].
({int start, int end}) lineRange(String text, int pos) {
  final s = pos == 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1;
  final rawEnd = text.indexOf('\n', pos);
  return (start: s, end: rawEnd == -1 ? text.length : rawEnd);
}

/// Toggles [prefix] comment on the line containing [cursor].
({String text, int cursor}) toggleCommentLine(
  String text,
  int cursor,
  String prefix,
) {
  final r = lineRange(text, cursor);
  final lineContent = text.substring(r.start, r.end);
  final trimmed = lineContent.trimLeft();
  final indent = lineContent.length - trimmed.length;
  String newLine;
  int delta;
  if (trimmed.startsWith(prefix)) {
    newLine =
        lineContent.substring(0, indent) + trimmed.substring(prefix.length);
    delta = -prefix.length;
  } else {
    newLine = lineContent.substring(0, indent) + prefix + trimmed;
    delta = prefix.length;
  }
  final newText = text.substring(0, r.start) + newLine + text.substring(r.end);
  return (
    text: newText,
    cursor: (cursor + delta).clamp(r.start, r.start + newLine.length),
  );
}

/// Duplicates the line containing [cursor] directly below it.
({String text, int cursor}) duplicateLineInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  final lineContent = text.substring(r.start, r.end);
  final newText =
      '${text.substring(0, r.end)}\n$lineContent${text.substring(r.end)}';
  return (text: newText, cursor: r.end + 1 + (cursor - r.start));
}

/// Deletes the line containing [cursor]. Returns null when there is nothing
/// to delete (single line without newline).
({String text, int cursor})? deleteLineInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  String newText;
  int newCursor;
  if (r.end < text.length) {
    newText = text.substring(0, r.start) + text.substring(r.end + 1);
    newCursor = r.start;
  } else if (r.start > 0) {
    newText = text.substring(0, r.start - 1);
    newCursor = r.start - 1;
  } else {
    return null;
  }
  return (text: newText, cursor: newCursor.clamp(0, newText.length));
}

/// Moves the line containing [cursor] one line up. Returns null when the
/// line is already the first line.
({String text, int cursor})? moveLineUpInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  if (r.start == 0) return null;
  final prev = lineRange(text, r.start - 1);
  final cur = text.substring(r.start, r.end);
  final above = text.substring(prev.start, prev.end);
  final before = text.substring(0, prev.start);
  final after = r.end < text.length ? text.substring(r.end) : '';
  final newText = '$before$cur\n$above$after';
  final off = cursor - r.start;
  return (text: newText, cursor: prev.start + off.clamp(0, cur.length));
}

/// Moves the line containing [cursor] one line down. Returns null when the
/// line is already the last line.
({String text, int cursor})? moveLineDownInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  if (r.end >= text.length) return null;
  final next = lineRange(text, r.end + 1);
  final cur = text.substring(r.start, r.end);
  final below = text.substring(next.start, next.end);
  final before = text.substring(0, r.start);
  final after = next.end < text.length ? text.substring(next.end) : '';
  final newText = '$before$below\n$cur$after';
  final off = cursor - r.start;
  final newLineStart = r.start + below.length + 1;
  return (text: newText, cursor: newLineStart + off.clamp(0, cur.length));
}

/// Indents the line containing [cursor] by two spaces.
({String text, int cursor}) indentLineInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  const sp = '  ';
  return (
    text: text.substring(0, r.start) + sp + text.substring(r.start),
    cursor: cursor + sp.length,
  );
}

/// Outdents the line containing [cursor] by up to two spaces. Returns null
/// when the line has no leading whitespace.
({String text, int cursor})? outdentLineInText(String text, int cursor) {
  final r = lineRange(text, cursor);
  final line = text.substring(r.start, r.end);
  final strip = line.startsWith('  ')
      ? 2
      : line.startsWith(' ')
      ? 1
      : 0;
  if (strip == 0) return null;
  return (
    text:
        text.substring(0, r.start) +
        line.substring(strip) +
        text.substring(r.end),
    cursor: (cursor - strip).clamp(r.start, text.length - strip),
  );
}

// ── Quick find ───────────────────────────────────────────────────────────────

/// Result of a quick-find scan: all match offsets and the index of the
/// current (nearest to the search origin) match.
class QuickFindMatches {
  const QuickFindMatches({required this.offsets, required this.current});

  final List<int> offsets;
  final int current;
}

/// Finds all case-insensitive occurrences of [query] in [text] and picks the
/// match nearest to (at or after) [searchOrigin], wrapping to the first match.
QuickFindMatches computeQuickFindMatches({
  required String text,
  required String query,
  required int searchOrigin,
}) {
  final offsets = <int>[];
  if (query.isNotEmpty) {
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();
    var start = 0;
    while (true) {
      final index = haystack.indexOf(needle, start);
      if (index == -1) break;
      offsets.add(index);
      start = index + 1;
    }
  }

  var current = 0;
  if (offsets.isNotEmpty) {
    final nearest = offsets.indexWhere((offset) => offset >= searchOrigin);
    current = nearest == -1 ? 0 : nearest;
  }
  return QuickFindMatches(offsets: offsets, current: current);
}

/// True when [character] is a printable character usable for search
/// typeahead (rejects null, empty and control characters).
bool isPrintableTypeaheadCharacter(String? character) =>
    character != null &&
    character.isNotEmpty &&
    !character.codeUnits.any((u) => u < 0x20);

/// Decision logic for quick-find character input.
bool shouldAcceptQuickFindCharacter({
  required bool modifierPressed,
  required String? character,
}) {
  if (modifierPressed) return false;
  return isPrintableTypeaheadCharacter(character);
}

/// Decision logic for native-search typeahead: returns true when the key
/// event should NOT be forwarded into the search pattern field.
bool shouldIgnoreTypeahead({
  required bool searchVisible,
  required bool patternFocused,
  required bool isKeyDownOrRepeat,
  required bool modifierPressed,
  required String? character,
}) {
  if (!searchVisible || patternFocused) return true;
  if (!isKeyDownOrRepeat) return true;
  if (modifierPressed) return true;
  return !isPrintableTypeaheadCharacter(character);
}

// ── Go to line ───────────────────────────────────────────────────────────────

/// Returns the text offset of the first character of 1-based [lineNumber].
int lineStartOffset(String text, int lineNumber) {
  final lines = text.split('\n');
  int offset = 0;
  for (int i = 0; i < lineNumber - 1 && i < lines.length; i++) {
    offset += lines[i].length + 1;
  }
  return offset.clamp(0, text.length);
}
