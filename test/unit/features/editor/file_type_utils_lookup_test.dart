import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/editor/utils/file_type_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forPath preserves every extension classification', () {
    void expectExtensions(
      List<String> extensions,
      IconData icon,
      Color color,
    ) {
      for (final extension in extensions) {
        final result = FileTypeUtils.forPath('dir/sample.$extension');
        expect(result.icon, icon, reason: extension);
        expect(result.color, color, reason: extension);
      }
    }

    expectExtensions(['dart'], Icons.flutter_dash, const Color(0xFF54C5F8));
    expectExtensions(['html', 'htm'], Icons.html, const Color(0xFFE34C26));
    expectExtensions(['css'], Icons.css, const Color(0xFF1572B6));
    expectExtensions(
      ['js', 'mjs', 'cjs'],
      Icons.javascript,
      const Color(0xFFF7DF1E),
    );
    expectExtensions(['ts', 'tsx'], Icons.code, const Color(0xFF3178C6));
    expectExtensions(['jsx'], Icons.code, const Color(0xFF61DAFB));
    expectExtensions(['vue'], Icons.code, const Color(0xFF42B883));
    expectExtensions(['svelte'], Icons.code, const Color(0xFFFF3E00));
    expectExtensions(
      ['py', 'pyi', 'pyw'],
      Icons.code,
      const Color(0xFF3776AB),
    );
    expectExtensions(['java'], Icons.coffee, const Color(0xFFB07219));
    expectExtensions(['kt', 'kts'], Icons.code, const Color(0xFF7F52FF));
    expectExtensions(['groovy'], Icons.code, const Color(0xFF4298B8));
    expectExtensions(['c', 'h'], Icons.code, const Color(0xFF555555));
    expectExtensions(
      ['cpp', 'cc', 'cxx', 'hpp'],
      Icons.code,
      const Color(0xFF004482),
    );
    expectExtensions(['cs'], Icons.code, const Color(0xFF9B4F96));
    expectExtensions(['swift'], Icons.code, const Color(0xFFF05138));
    expectExtensions(['m', 'mm'], Icons.code, const Color(0xFF438EFF));
    expectExtensions(['go'], Icons.code, const Color(0xFF00ADD8));
    expectExtensions(['rs'], Icons.code, const Color(0xFFDEA584));
    expectExtensions(['rb', 'erb'], Icons.code, const Color(0xFFCC342D));
    expectExtensions(['php'], Icons.code, const Color(0xFF777BB4));
    expectExtensions(
      ['sh', 'bash', 'zsh', 'fish'],
      Icons.terminal,
      const Color(0xFF4EAA25),
    );
    expectExtensions(
      ['ps1', 'psm1'],
      Icons.terminal,
      const Color(0xFF012456),
    );
    expectExtensions(
      ['json', 'jsonc'],
      Icons.data_object,
      const Color(0xFFCBCB41),
    );
    expectExtensions(
      ['yaml', 'yml'],
      Icons.settings_input_component,
      const Color(0xFFCB171E),
    );
    expectExtensions(['toml'], Icons.settings, const Color(0xFF9C4121));
    expectExtensions(['xml'], Icons.code, const Color(0xFFF1672C));
    expectExtensions(['env'], Icons.lock_outline, const Color(0xFFECD53F));
    expectExtensions(
      ['ini', 'cfg', 'conf', 'properties'],
      Icons.tune,
      const Color(0xFF999999),
    );
    expectExtensions(
      ['md', 'mdx', 'markdown', 'rst'],
      Icons.description,
      const Color(0xFF519ABA),
    );
    expectExtensions(['txt'], Icons.article_outlined, const Color(0xFF888888));
    expectExtensions(['pdf'], Icons.picture_as_pdf, const Color(0xFFE53935));
    expectExtensions(
      ['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif'],
      Icons.image_outlined,
      const Color(0xFF26A69A),
    );
    expectExtensions(['svg', 'ico'], Icons.image, const Color(0xFFFF9800));
    expectExtensions(
      ['ttf', 'otf', 'woff', 'woff2'],
      Icons.font_download_outlined,
      const Color(0xFF9575CD),
    );
    expectExtensions(
      ['zip', 'tar', 'gz', 'bz2', 'xz', 'rar', '7z'],
      Icons.folder_zip_outlined,
      const Color(0xFFFFCA28),
    );
    expectExtensions(['lock'], Icons.lock_outline, const Color(0xFFBDBDBD));
    expectExtensions(
      ['pubspec'],
      Icons.flutter_dash,
      const Color(0xFF54C5F8),
    );
    expectExtensions(
      ['gitignore', 'gitattributes', 'gitmodules'],
      Icons.merge,
      const Color(0xFFF05133),
    );
    expectExtensions(
      ['dockerfile'],
      Icons.dns_outlined,
      const Color(0xFF2496ED),
    );
    expectExtensions(['sql'], Icons.storage, const Color(0xFF336791));
  });

  test('forPath preserves name-based and fallback behavior', () {
    final dockerfile = FileTypeUtils.forPath('project/Dockerfile');
    expect(dockerfile.icon, Icons.dns_outlined);
    expect(dockerfile.color, const Color(0xFF2496ED));

    final dotfile = FileTypeUtils.forPath('project/.unknown');
    expect(dotfile.icon, Icons.settings_outlined);
    expect(dotfile.color, const Color(0xFF777777));

    for (final path in ['README', 'project/file.unknown']) {
      final result = FileTypeUtils.forPath(path);
      expect(result.icon, Icons.insert_drive_file_outlined, reason: path);
      expect(result.color, const Color(0xFF90A4AE), reason: path);
    }
  });

  test('languageFor preserves every mapping and fallback', () {
    const expected = <String, String>{
      'dart': 'dart',
      'js': 'javascript',
      'mjs': 'javascript',
      'ts': 'typescript',
      'jsx': 'xml',
      'tsx': 'xml',
      'py': 'python',
      'java': 'java',
      'kt': 'kotlin',
      'go': 'go',
      'rs': 'rust',
      'rb': 'ruby',
      'php': 'php',
      'sh': 'bash',
      'bash': 'bash',
      'zsh': 'bash',
      'c': 'c',
      'h': 'c',
      'cpp': 'cpp',
      'cc': 'cpp',
      'cxx': 'cpp',
      'cs': 'csharp',
      'swift': 'swift',
      'html': 'xml',
      'htm': 'xml',
      'css': 'css',
      'json': 'json',
      'yaml': 'yaml',
      'yml': 'yaml',
      'env': 'dotenv',
      'xml': 'xml',
      'svg': 'xml',
      'sql': 'sql',
      'md': 'markdown',
      'markdown': 'markdown',
    };

    for (final entry in expected.entries) {
      expect(
        FileTypeUtils.languageFor('dir/sample.${entry.key}'),
        entry.value,
        reason: entry.key,
      );
    }
    for (final path in ['.env', '.env.local', '.env.custom']) {
      expect(FileTypeUtils.languageFor(path), 'dotenv', reason: path);
    }
    expect(FileTypeUtils.languageFor('MAIN.DART'), 'dart');
    expect(FileTypeUtils.languageFor('file.unknown'), isNull);
    expect(FileTypeUtils.languageFor('README'), isNull);
  });
}
