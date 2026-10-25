import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:yoloit/features/editor/utils/editor_language_registry.dart';

void main() {
  test('forPath preserves every extension language classification', () {
    void expectExtensions(
      List<String> extensions, {
      required String id,
      required String label,
      Mode? mode,
      String commentPrefix = '// ',
    }) {
      for (final extension in extensions) {
        final spec = EditorLanguageRegistry.forPath('lib/sample.$extension');
        expect(spec.id, id, reason: extension);
        expect(spec.label, label, reason: extension);
        expect(spec.mode, same(mode), reason: extension);
        expect(spec.commentPrefix, commentPrefix, reason: extension);
      }
    }

    expectExtensions(['dart'], id: 'dart', label: 'Dart', mode: dart);
    expectExtensions(
      ['js', 'mjs', 'cjs'],
      id: 'javascript',
      label: 'JavaScript',
      mode: javascript,
    );
    expectExtensions(
      ['ts'],
      id: 'typescript',
      label: 'TypeScript',
      mode: typescript,
    );
    expectExtensions(['jsx', 'tsx'], id: 'react', label: 'React', mode: xml);
    expectExtensions(
      ['py', 'pyi', 'pyw'],
      id: 'python',
      label: 'Python',
      mode: python,
      commentPrefix: '# ',
    );
    expectExtensions(['java'], id: 'java', label: 'Java', mode: java);
    expectExtensions(
      ['kt', 'kts'],
      id: 'kotlin',
      label: 'Kotlin',
      mode: kotlin,
    );
    expectExtensions(['go'], id: 'go', label: 'Go', mode: go);
    expectExtensions(['rs'], id: 'rust', label: 'Rust', mode: rust);
    expectExtensions(
      ['sh', 'bash', 'zsh', 'fish'],
      id: 'shell',
      label: 'Shell',
      mode: bash,
      commentPrefix: '# ',
    );
    expectExtensions(['c', 'h'], id: 'c', label: 'C', mode: cpp);
    expectExtensions(
      ['cpp', 'cc', 'cxx', 'hpp'],
      id: 'cpp',
      label: 'C++',
      mode: cpp,
    );
    expectExtensions(['css'], id: 'css', label: 'CSS', mode: css);
    expectExtensions(
      ['json', 'jsonc'],
      id: 'json',
      label: 'JSON',
      mode: json,
    );
    expectExtensions(
      ['yaml', 'yml'],
      id: 'yaml',
      label: 'YAML',
      mode: yaml,
      commentPrefix: '# ',
    );
    expectExtensions(
      ['toml', 'ini', 'cfg', 'conf', 'properties'],
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    );
    expectExtensions(['xml'], id: 'xml', label: 'XML', mode: xml);
    expectExtensions(['svg'], id: 'xml', label: 'SVG', mode: xml);
    expectExtensions(['html', 'htm'], id: 'xml', label: 'HTML', mode: xml);
    expectExtensions(['sql'], id: 'sql', label: 'SQL', mode: sql);
    expectExtensions(
      ['md', 'mdx', 'markdown'],
      id: 'markdown',
      label: 'Markdown',
      commentPrefix: '<!-- ',
    );
    expectExtensions(['swift'], id: 'swift', label: 'Swift', mode: swift);
  });

  test('forPath preserves dotenv and Dockerfile precedence', () {
    const dotenvPaths = [
      '.env',
      '.env.local',
      '.env.development',
      '.env.production',
      '.env.test',
      '.env.example',
      '.env.sample',
      '.env.custom',
      'config.env',
      '/tmp/.ENV',
      'dockerfile.env',
    ];
    for (final path in dotenvPaths) {
      final spec = EditorLanguageRegistry.forPath(path);
      expect(spec.id, 'dotenv', reason: path);
      expect(spec.label, 'ENV', reason: path);
      expect(spec.mode, same(bash), reason: path);
      expect(spec.commentPrefix, '# ', reason: path);
    }

    final dockerfile = EditorLanguageRegistry.forPath('/tmp/Dockerfile');
    expect(dockerfile.id, 'dockerfile');
    expect(dockerfile.label, 'Dockerfile');
    expect(dockerfile.mode, same(bash));
    expect(dockerfile.commentPrefix, '# ');
  });

  test('forPath preserves extension extraction and fallbacks', () {
    expect(EditorLanguageRegistry.forPath('nested/MAIN.DART').id, 'dart');

    for (final path in ['README', '.gitignore', 'trailing.']) {
      final spec = EditorLanguageRegistry.forPath(path);
      expect(spec.id, 'plaintext', reason: path);
      expect(spec.label, 'Plain Text', reason: path);
      expect(spec.mode, isNull, reason: path);
      expect(spec.commentPrefix, '// ', reason: path);
    }

    final unknown = EditorLanguageRegistry.forPath('file.custom');
    expect(unknown.id, 'custom');
    expect(unknown.label, 'CUSTOM');
    expect(unknown.mode, isNull);
    expect(unknown.commentPrefix, '// ');
  });
}
