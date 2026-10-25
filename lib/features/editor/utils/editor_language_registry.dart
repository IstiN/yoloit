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

  static final _languageFactories = <String, EditorLanguageSpec Function()>{
    'dart': () => EditorLanguageSpec(id: 'dart', label: 'Dart', mode: dart),
    'js': () => EditorLanguageSpec(
      id: 'javascript',
      label: 'JavaScript',
      mode: javascript,
    ),
    'mjs': () => EditorLanguageSpec(
      id: 'javascript',
      label: 'JavaScript',
      mode: javascript,
    ),
    'cjs': () => EditorLanguageSpec(
      id: 'javascript',
      label: 'JavaScript',
      mode: javascript,
    ),
    'ts': () => EditorLanguageSpec(
      id: 'typescript',
      label: 'TypeScript',
      mode: typescript,
    ),
    'jsx': () => EditorLanguageSpec(id: 'react', label: 'React', mode: xml),
    'tsx': () => EditorLanguageSpec(id: 'react', label: 'React', mode: xml),
    'py': () => EditorLanguageSpec(
      id: 'python',
      label: 'Python',
      mode: python,
      commentPrefix: '# ',
    ),
    'pyi': () => EditorLanguageSpec(
      id: 'python',
      label: 'Python',
      mode: python,
      commentPrefix: '# ',
    ),
    'pyw': () => EditorLanguageSpec(
      id: 'python',
      label: 'Python',
      mode: python,
      commentPrefix: '# ',
    ),
    'java': () => EditorLanguageSpec(id: 'java', label: 'Java', mode: java),
    'kt': () => EditorLanguageSpec(id: 'kotlin', label: 'Kotlin', mode: kotlin),
    'kts': () =>
        EditorLanguageSpec(id: 'kotlin', label: 'Kotlin', mode: kotlin),
    'go': () => EditorLanguageSpec(id: 'go', label: 'Go', mode: go),
    'rs': () => EditorLanguageSpec(id: 'rust', label: 'Rust', mode: rust),
    'sh': () => EditorLanguageSpec(
      id: 'shell',
      label: 'Shell',
      mode: bash,
      commentPrefix: '# ',
    ),
    'bash': () => EditorLanguageSpec(
      id: 'shell',
      label: 'Shell',
      mode: bash,
      commentPrefix: '# ',
    ),
    'zsh': () => EditorLanguageSpec(
      id: 'shell',
      label: 'Shell',
      mode: bash,
      commentPrefix: '# ',
    ),
    'fish': () => EditorLanguageSpec(
      id: 'shell',
      label: 'Shell',
      mode: bash,
      commentPrefix: '# ',
    ),
    'c': () => EditorLanguageSpec(id: 'c', label: 'C', mode: cpp),
    'h': () => EditorLanguageSpec(id: 'c', label: 'C', mode: cpp),
    'cpp': () => EditorLanguageSpec(id: 'cpp', label: 'C++', mode: cpp),
    'cc': () => EditorLanguageSpec(id: 'cpp', label: 'C++', mode: cpp),
    'cxx': () => EditorLanguageSpec(id: 'cpp', label: 'C++', mode: cpp),
    'hpp': () => EditorLanguageSpec(id: 'cpp', label: 'C++', mode: cpp),
    'css': () => EditorLanguageSpec(id: 'css', label: 'CSS', mode: css),
    'json': () => EditorLanguageSpec(id: 'json', label: 'JSON', mode: json),
    'jsonc': () => EditorLanguageSpec(id: 'json', label: 'JSON', mode: json),
    'yaml': () => EditorLanguageSpec(
      id: 'yaml',
      label: 'YAML',
      mode: yaml,
      commentPrefix: '# ',
    ),
    'yml': () => EditorLanguageSpec(
      id: 'yaml',
      label: 'YAML',
      mode: yaml,
      commentPrefix: '# ',
    ),
    'toml': () => const EditorLanguageSpec(
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    ),
    'ini': () => const EditorLanguageSpec(
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    ),
    'cfg': () => const EditorLanguageSpec(
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    ),
    'conf': () => const EditorLanguageSpec(
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    ),
    'properties': () => const EditorLanguageSpec(
      id: 'config',
      label: 'Config',
      commentPrefix: '# ',
    ),
    'xml': () => EditorLanguageSpec(id: 'xml', label: 'XML', mode: xml),
    'svg': () => EditorLanguageSpec(id: 'xml', label: 'SVG', mode: xml),
    'html': () => EditorLanguageSpec(id: 'xml', label: 'HTML', mode: xml),
    'htm': () => EditorLanguageSpec(id: 'xml', label: 'HTML', mode: xml),
    'sql': () => EditorLanguageSpec(id: 'sql', label: 'SQL', mode: sql),
    'md': () => const EditorLanguageSpec(
      id: 'markdown',
      label: 'Markdown',
      commentPrefix: '<!-- ',
    ),
    'mdx': () => const EditorLanguageSpec(
      id: 'markdown',
      label: 'Markdown',
      commentPrefix: '<!-- ',
    ),
    'markdown': () => const EditorLanguageSpec(
      id: 'markdown',
      label: 'Markdown',
      commentPrefix: '<!-- ',
    ),
    'swift': () => EditorLanguageSpec(id: 'swift', label: 'Swift', mode: swift),
  };

  static EditorLanguageSpec forPath(String path) {
    final name = _fileName(path).toLowerCase();
    final ext = _extension(name);

    if (_dotenvNames.contains(name) ||
        name.startsWith('.env.') ||
        ext == 'env') {
      return EditorLanguageSpec(
        id: 'dotenv',
        label: 'ENV',
        mode: bash,
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

    final factory = _languageFactories[ext];
    if (factory != null) return factory();
    return EditorLanguageSpec(
      id: ext.isEmpty ? 'plaintext' : ext,
      label: ext.isEmpty ? 'Plain Text' : ext.toUpperCase(),
    );
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
