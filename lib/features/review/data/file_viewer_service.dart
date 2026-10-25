import 'dart:io';

import 'package:yoloit/features/editor/utils/editor_language_registry.dart';

class FileViewerService {
  const FileViewerService._();
  static const FileViewerService instance = FileViewerService._();

  static const _maxFileSize = 2 * 1024 * 1024; // 2MB

  Future<FileViewResult> readFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const FileViewResult.error('File not found');
      }
      final stat = file.statSync();
      if (stat.size > _maxFileSize) {
        return const FileViewResult.error('File too large to display (>2MB)');
      }
      final content = await file.readAsString();
      final language = _detectLanguage(path);
      return FileViewResult.success(content: content, language: language);
    } catch (e) {
      return FileViewResult.error(e.toString());
    }
  }

  /// Extensions the viewer recognizes; anything else is plaintext.
  ///
  /// Characterization of the original switch in this file: extensions the
  /// viewer never mapped must keep returning 'plaintext' even when the
  /// editor registry knows them.
  static const _knownExtensions = <String>{
    'dart',
    'js',
    'jsx',
    'ts',
    'tsx',
    'py',
    'rs',
    'go',
    'java',
    'kt',
    'swift',
    'c',
    'h',
    'cpp',
    'cc',
    'cxx',
    'hpp',
    'cs',
    'rb',
    'php',
    'html',
    'htm',
    'css',
    'scss',
    'sass',
    'json',
    'yaml',
    'yml',
    'xml',
    'md',
    'markdown',
    'sh',
    'bash',
    'zsh',
    'sql',
    'toml',
  };

  /// Registry language ids that intentionally differ from viewer ids.
  static const _languageIdOverrides = <String, String>{
    'jsx': 'javascript',
    'tsx': 'typescript',
    'html': 'html',
    'htm': 'html',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'cs': 'csharp',
    'rb': 'ruby',
    'php': 'php',
    'scss': 'scss',
    'sass': 'scss',
    'toml': 'toml',
  };

  String _detectLanguage(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (!_knownExtensions.contains(ext)) return 'plaintext';
    return _languageIdOverrides[ext] ?? EditorLanguageRegistry.forPath(path).id;
  }
}

class FileViewResult {
  const FileViewResult._({this.content, this.language, this.error});

  const FileViewResult.success({required String content, required String language})
      : this._(content: content, language: language);

  const FileViewResult.error(String error) : this._(error: error);

  final String? content;
  final String? language;
  final String? error;

  bool get isSuccess => error == null;
}
