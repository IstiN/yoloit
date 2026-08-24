// Regression guard for two perf rules from `AGENTS.md`:
//
//   1. `Color.withOpacity(x)` (double 0..1) triggers a save-layer compositing
//      pass. Prefer `.withValues(alpha: x)` for static/partial transparency.
//   2. `Opacity(opacity: 0)` / `Opacity(opacity: 1)` (binary) keeps the
//      subtree in the render tree. Prefer `Visibility` (or `Offstage`) so
//      the subtree is removed entirely.
//
// The test walks every `*.dart` under `lib/` and asserts zero matches for
// either pattern. Animated/fractional uses are legitimate and are excluded
// by the patterns (we only flag the static-binary forms).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _libRoot = 'lib';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AGENTS.md perf rule compliance (lib/)', () {
    final offenders = <_Offender>[];

    setUpAll(() {
      final root = Directory(_libRoot);
      if (!root.existsSync()) {
        throw StateError(
          'Expected lib/ at repo root, but ${root.absolute.path} is missing.',
        );
      }
      for (final file in root.listSync(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.dart')) continue;
        // Skip generated files (analyzer already excludes these, but be
        // defensive against new generators landing outside analysis_options).
        final basename = file.uri.pathSegments.last;
        if (basename.endsWith('.g.dart') ||
            basename.endsWith('.freezed.dart') ||
            basename.endsWith('.mocks.dart')) {
          continue;
        }
        final content = file.readAsStringSync();
        final lineStarts = _lineStartOffsets(content);

        // Rule 1: no `.withOpacity(` — that double-precision helper
        // triggers a save-layer compositing pass.
        for (final m in _withOpacityRegex.allMatches(content)) {
          offenders.add(
            _Offender(
              file: file.path,
              line: _offsetToLine(lineStarts, m.start),
              rule: 'no withOpacity',
              snippet: content
                  .substring(_lineStart(lineStarts, m.start), m.end)
                  .trim(),
            ),
          );
        }

        // Rule 2: no binary `Opacity(opacity: 0` / `Opacity(opacity: 1`.
        // We allow whitespace/newlines between `Opacity(`, `opacity:` and
        // the value (multi-line constructors are idiomatic). The value
        // must be exactly `0` or `1` — not followed by another digit or
        // dot — so legitimate fractions like `0.4`, `1.0`, `100` and
        // animated values like `opacity: fade` are not flagged.
        for (final m in _binaryOpacityRegex.allMatches(content)) {
          offenders.add(
            _Offender(
              file: file.path,
              line: _offsetToLine(lineStarts, m.start),
              rule: 'no binary Opacity(opacity: 0|1)',
              snippet: content
                  .substring(_lineStart(lineStarts, m.start), m.end)
                  .trim(),
            ),
          );
        }
      }
    });

    test('no .withOpacity( usage in lib/**/*.dart', () {
      final hits = offenders
          .where((o) => o.rule == 'no withOpacity')
          .toList(growable: false);
      if (hits.isNotEmpty) {
        fail(
          'Found ${hits.length} .withOpacity( call(s) in lib/. '
          'AGENTS.md requires .withValues(alpha: ...) instead.\n'
          '${hits.map((o) => '  - ${o.file}:${o.line}  ${o.snippet}').join('\n')}',
        );
      }
    });

    test('no binary Opacity(opacity: 0|1) in lib/**/*.dart', () {
      final hits = offenders
          .where((o) => o.rule == 'no binary Opacity(opacity: 0|1)')
          .toList(growable: false);
      if (hits.isNotEmpty) {
        fail(
          'Found ${hits.length} binary Opacity(opacity: 0|1) usage(s) in '
          'lib/. AGENTS.md requires Visibility (or Offstage) so the '
          'subtree is removed from the render tree.\n'
          '${hits.map((o) => '  - ${o.file}:${o.line}  ${o.snippet}').join('\n')}',
        );
      }
    });
  });
}

// `.withOpacity(` — anchored to `.` so we don't catch unrelated identifiers
// like `somethingWithOpacity(` or comments mentioning `withOpacity`.
// Both `.withOpacity(` (the Color call) and `Color.withOpacity(` are caught,
// which is what we want.
final RegExp _withOpacityRegex = RegExp(r'\.withOpacity\(');

// `Opacity(\s*opacity:\s*[01](?![0-9.])` — same trailing anchor as before,
// plus `\s*` (not `\s+`) so `Opacity(opacity:0)` (no space) is also caught.
final RegExp _binaryOpacityRegex = RegExp(
  r'Opacity\(\s*opacity:\s*[01](?![0-9.])',
);

// Returns the byte offset of the start of every line in [content].
List<int> _lineStartOffsets(String content) {
  final out = <int>[0];
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x0A /* \n */ && i + 1 < content.length) {
      out.add(i + 1);
    }
  }
  return out;
}

// 1-based line number for a byte offset.
int _offsetToLine(List<int> lineStarts, int offset) {
  // Binary search would be cheaper, but the list is usually small enough.
  for (var i = lineStarts.length - 1; i >= 0; i--) {
    if (lineStarts[i] <= offset) return i + 1;
  }
  return 1;
}

// Byte offset of the start of the line containing [offset].
int _lineStart(List<int> lineStarts, int offset) =>
    lineStarts[_offsetToLine(lineStarts, offset) - 1];

class _Offender {
  const _Offender({
    required this.file,
    required this.line,
    required this.rule,
    required this.snippet,
  });

  final String file;
  final int line;
  final String rule;
  final String snippet;
}