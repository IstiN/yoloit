import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/review/data/file_viewer_service.dart';

void main() {
  const service = FileViewerService.instance;

  group('FileViewerService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_viewer_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns success result for readable file', () async {
      final file = File('${tempDir.path}/hello.dart');
      await file.writeAsString('void main() => print("hello");');

      final result = await service.readFile(file.path);

      expect(result.isSuccess, isTrue);
      expect(result.content, contains('void main()'));
      expect(result.language, 'dart');
    });

    test('returns error for non-existent file', () async {
      final result = await service.readFile('${tempDir.path}/nonexistent.txt');

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('not found'));
    });

    test('preserves every extension language classification', () async {
      // Characterization of the original `_detectLanguage` switch in this
      // file (git show HEAD). Every key it supported must keep mapping to
      // the same language id after delegating to EditorLanguageRegistry.
      const legacyMapping = <String, String>{
        'dart': 'dart',
        'js': 'javascript',
        'jsx': 'javascript',
        'ts': 'typescript',
        'tsx': 'typescript',
        'py': 'python',
        'rs': 'rust',
        'go': 'go',
        'java': 'java',
        'kt': 'kotlin',
        'swift': 'swift',
        'c': 'c',
        'h': 'c',
        'cpp': 'cpp',
        'cc': 'cpp',
        'cxx': 'cpp',
        'hpp': 'cpp',
        'cs': 'csharp',
        'rb': 'ruby',
        'php': 'php',
        'html': 'html',
        'htm': 'html',
        'css': 'css',
        'scss': 'scss',
        'sass': 'scss',
        'json': 'json',
        'yaml': 'yaml',
        'yml': 'yaml',
        'xml': 'xml',
        'md': 'markdown',
        'markdown': 'markdown',
        'sh': 'bash',
        'bash': 'bash',
        'zsh': 'bash',
        'sql': 'sql',
        'toml': 'toml',
      };

      for (final entry in legacyMapping.entries) {
        final file = File('${tempDir.path}/sample.${entry.key}');
        await file.writeAsString('content');
        final result = await service.readFile(file.path);
        expect(result.language, entry.value, reason: 'for .${entry.key}');
      }

      // Extensions the legacy switch did not support stay plaintext, even
      // when the editor registry knows them.
      const legacyUnknown = [
        'txt',
        'mjs',
        'cjs',
        'pyi',
        'pyw',
        'kts',
        'fish',
        'jsonc',
        'ini',
        'cfg',
        'conf',
        'properties',
        'svg',
        'mdx',
        'env',
      ];
      for (final ext in legacyUnknown) {
        final file = File('${tempDir.path}/sample.$ext');
        await file.writeAsString('content');
        final result = await service.readFile(file.path);
        expect(result.language, 'plaintext', reason: 'for .$ext');
      }

      for (final name in ['README', '.gitignore', '.env', '.env.local']) {
        final file = File('${tempDir.path}/$name');
        await file.writeAsString('content');
        final result = await service.readFile(file.path);
        expect(result.language, 'plaintext', reason: 'for $name');
      }
    });

    test('detects language from extension correctly', () async {
      final cases = {
        'file.dart': 'dart',
        'file.js': 'javascript',
        'file.ts': 'typescript',
        'file.py': 'python',
        'file.rs': 'rust',
        'file.go': 'go',
        'file.yaml': 'yaml',
        'file.json': 'json',
        'file.md': 'markdown',
        'file.sh': 'bash',
        'file.unknown': 'plaintext',
      };

      for (final entry in cases.entries) {
        final file = File('${tempDir.path}/${entry.key}');
        await file.writeAsString('content');
        final result = await service.readFile(file.path);
        expect(result.language, entry.value, reason: 'for ${entry.key}');
      }
    });

    test('reads multi-line file content correctly', () async {
      const content = 'line 1\nline 2\nline 3';
      final file = File('${tempDir.path}/multi.txt');
      await file.writeAsString(content);

      final result = await service.readFile(file.path);

      expect(result.content, content);
    });
  });
}
