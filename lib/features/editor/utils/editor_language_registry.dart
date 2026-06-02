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

class EditorLanguageRegistry {
  const EditorLanguageRegistry._();

  static EditorLanguageSpec forPath(String path) {
    final name = _fileName(path).toLowerCase();
    final ext = _extension(name);

    if (_dotenvNames.contains(name) || ext == 'env') {
      return const EditorLanguageSpec(
        id: 'dotenv',
        label: 'ENV',
        commentPrefix: '# ',
      );
    }
    if (name == 'dockerfile') {
      return EditorLanguageSpec(
        id: 'dockerfile',
        label: 'Dockerfile',
        mode: bash,
        commentPrefix: '# ',
      );
    }

    return switch (ext) {
      'dart' => EditorLanguageSpec(id: 'dart', label: 'Dart', mode: dart),
      'js' || 'mjs' || 'cjs' => EditorLanguageSpec(
        id: 'javascript',
        label: 'JavaScript',
        mode: javascript,
      ),
      'ts' => EditorLanguageSpec(
        id: 'typescript',
        label: 'TypeScript',
        mode: typescript,
      ),
      'jsx' ||
      'tsx' => EditorLanguageSpec(id: 'react', label: 'React', mode: xml),
      'py' || 'pyi' || 'pyw' => EditorLanguageSpec(
        id: 'python',
        label: 'Python',
        mode: python,
        commentPrefix: '# ',
      ),
      'java' => EditorLanguageSpec(id: 'java', label: 'Java', mode: java),
      'kt' ||
      'kts' => EditorLanguageSpec(id: 'kotlin', label: 'Kotlin', mode: kotlin),
      'go' => EditorLanguageSpec(id: 'go', label: 'Go', mode: go),
      'rs' => EditorLanguageSpec(id: 'rust', label: 'Rust', mode: rust),
      'sh' || 'bash' || 'zsh' || 'fish' => EditorLanguageSpec(
        id: 'shell',
        label: 'Shell',
        mode: bash,
        commentPrefix: '# ',
      ),
      'c' || 'h' => EditorLanguageSpec(id: 'c', label: 'C', mode: cpp),
      'cpp' ||
      'cc' ||
      'cxx' ||
      'hpp' => EditorLanguageSpec(id: 'cpp', label: 'C++', mode: cpp),
      'css' => EditorLanguageSpec(id: 'css', label: 'CSS', mode: css),
      'json' ||
      'jsonc' => EditorLanguageSpec(id: 'json', label: 'JSON', mode: json),
      'yaml' || 'yml' => EditorLanguageSpec(
        id: 'yaml',
        label: 'YAML',
        mode: yaml,
        commentPrefix: '# ',
      ),
      'toml' ||
      'ini' ||
      'cfg' ||
      'conf' ||
      'properties' => const EditorLanguageSpec(
        id: 'config',
        label: 'Config',
        commentPrefix: '# ',
      ),
      'xml' || 'svg' || 'html' || 'htm' => EditorLanguageSpec(
        id: 'xml',
        label:
            ext == 'svg'
                ? 'SVG'
                : ext == 'xml'
                ? 'XML'
                : 'HTML',
        mode: xml,
      ),
      'sql' => EditorLanguageSpec(id: 'sql', label: 'SQL', mode: sql),
      'md' || 'mdx' || 'markdown' => const EditorLanguageSpec(
        id: 'markdown',
        label: 'Markdown',
        commentPrefix: '<!-- ',
      ),
      'swift' => EditorLanguageSpec(id: 'swift', label: 'Swift', mode: swift),
      _ => EditorLanguageSpec(
        id: ext.isEmpty ? 'plaintext' : ext,
        label: ext.isEmpty ? 'Plain Text' : ext.toUpperCase(),
      ),
    };
  }

  static String _fileName(String path) {
    final slash = path.lastIndexOf('/');
    return slash == -1 ? path : path.substring(slash + 1);
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  static const _dotenvNames = {
    '.env',
    '.env.local',
    '.env.development',
    '.env.production',
    '.env.test',
    '.env.example',
    '.env.sample',
  };
}

class EditorLanguageSpec {
  const EditorLanguageSpec({
    required this.id,
    required this.label,
    this.mode,
    this.commentPrefix = '// ',
  });

  final String id;
  final String label;
  final Mode? mode;
  final String commentPrefix;
}
