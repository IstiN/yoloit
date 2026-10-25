import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:yoloit/features/board/plugins/builtin/code_snippet_plugin.dart';

void main() {
  test('code snippet language lookup covers every supported mode', () {
    final expectedModes = <String, Mode>{
      'dart': dart,
      'python': python,
      'javascript': javascript,
      'typescript': typescript,
      'bash': bash,
      'json': json,
      'yaml': yaml,
      'sql': sql,
      'kotlin': kotlin,
      'swift': swift,
    };

    for (final entry in expectedModes.entries) {
      expect(
        debugCodeSnippetModeFor(entry.key),
        same(entry.value),
        reason: entry.key,
      );
    }
  });

  test('code snippet language lookup falls back to Dart', () {
    for (final language in ['ruby', '', 'DART']) {
      expect(
        debugCodeSnippetModeFor(language),
        same(dart),
        reason: language,
      );
    }
  });
}
