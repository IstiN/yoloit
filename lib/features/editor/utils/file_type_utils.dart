import 'package:flutter/material.dart';

/// Maps file extensions to Material icons and accent colors.
class FileTypeUtils {
  const FileTypeUtils._();

  static const Color _cC = Color(0xFF555555);
  static const Color _cConfig = Color(0xFF999999);
  static const Color _cCpp = Color(0xFF004482);
  static const Color _cDoc = Color(0xFF519ABA);
  static const Color _cDocker = Color(0xFF2496ED);
  static const Color _cFlutter = Color(0xFF54C5F8);
  static const Color _cFont = Color(0xFF9575CD);
  static const Color _cGit = Color(0xFFF05133);
  static const Color _cHtml = Color(0xFFE34C26);
  static const Color _cImage = Color(0xFF26A69A);
  static const Color _cJs = Color(0xFFF7DF1E);
  static const Color _cJson = Color(0xFFCBCB41);
  static const Color _cKt = Color(0xFF7F52FF);
  static const Color _cObjc = Color(0xFF438EFF);
  static const Color _cPwsh = Color(0xFF012456);
  static const Color _cPy = Color(0xFF3776AB);
  static const Color _cRb = Color(0xFFCC342D);
  static const Color _cShell = Color(0xFF4EAA25);
  static const Color _cSvg = Color(0xFFFF9800);
  static const Color _cTs = Color(0xFF3178C6);
  static const Color _cYaml = Color(0xFFCB171E);
  static const Color _cZip = Color(0xFFFFCA28);

  static const _fileTypes = <String, ({IconData icon, Color color})>{
    // Dart / Flutter
    'dart': (icon: Icons.flutter_dash, color: _cFlutter),

    // Web
    'html': (icon: Icons.html, color: _cHtml),
    'htm': (icon: Icons.html, color: _cHtml),
    'css': (icon: Icons.css, color: Color(0xFF1572B6)),
    'js': (icon: Icons.javascript, color: _cJs),
    'mjs': (icon: Icons.javascript, color: _cJs),
    'cjs': (icon: Icons.javascript, color: _cJs),
    'ts': (icon: Icons.code, color: _cTs),
    'tsx': (icon: Icons.code, color: _cTs),
    'jsx': (icon: Icons.code, color: Color(0xFF61DAFB)),
    'vue': (icon: Icons.code, color: Color(0xFF42B883)),
    'svelte': (icon: Icons.code, color: Color(0xFFFF3E00)),

    // Python
    'py': (icon: Icons.code, color: _cPy),
    'pyi': (icon: Icons.code, color: _cPy),
    'pyw': (icon: Icons.code, color: _cPy),

    // JVM
    'java': (icon: Icons.coffee, color: Color(0xFFB07219)),
    'kt': (icon: Icons.code, color: _cKt),
    'kts': (icon: Icons.code, color: _cKt),
    'groovy': (icon: Icons.code, color: Color(0xFF4298B8)),

    // C family
    'c': (icon: Icons.code, color: _cC),
    'h': (icon: Icons.code, color: _cC),
    'cpp': (icon: Icons.code, color: _cCpp),
    'cc': (icon: Icons.code, color: _cCpp),
    'cxx': (icon: Icons.code, color: _cCpp),
    'hpp': (icon: Icons.code, color: _cCpp),
    'cs': (icon: Icons.code, color: Color(0xFF9B4F96)),

    // Swift / ObjC
    'swift': (icon: Icons.code, color: Color(0xFFF05138)),
    'm': (icon: Icons.code, color: _cObjc),
    'mm': (icon: Icons.code, color: _cObjc),

    // Go / Rust / Ruby / PHP
    'go': (icon: Icons.code, color: Color(0xFF00ADD8)),
    'rs': (icon: Icons.code, color: Color(0xFFDEA584)),
    'rb': (icon: Icons.code, color: _cRb),
    'erb': (icon: Icons.code, color: _cRb),
    'php': (icon: Icons.code, color: Color(0xFF777BB4)),

    // Shell
    'sh': (icon: Icons.terminal, color: _cShell),
    'bash': (icon: Icons.terminal, color: _cShell),
    'zsh': (icon: Icons.terminal, color: _cShell),
    'fish': (icon: Icons.terminal, color: _cShell),
    'ps1': (icon: Icons.terminal, color: _cPwsh),
    'psm1': (icon: Icons.terminal, color: _cPwsh),

    // Data / Config
    'json': (icon: Icons.data_object, color: _cJson),
    'jsonc': (icon: Icons.data_object, color: _cJson),
    'yaml': (
      icon: Icons.settings_input_component,
      color: _cYaml,
    ),
    'yml': (
      icon: Icons.settings_input_component,
      color: _cYaml,
    ),
    'toml': (icon: Icons.settings, color: Color(0xFF9C4121)),
    'xml': (icon: Icons.code, color: Color(0xFFF1672C)),
    'env': (icon: Icons.lock_outline, color: Color(0xFFECD53F)),
    'ini': (icon: Icons.tune, color: _cConfig),
    'cfg': (icon: Icons.tune, color: _cConfig),
    'conf': (icon: Icons.tune, color: _cConfig),
    'properties': (icon: Icons.tune, color: _cConfig),

    // Markdown / Docs
    'md': (icon: Icons.description, color: _cDoc),
    'mdx': (icon: Icons.description, color: _cDoc),
    'markdown': (icon: Icons.description, color: _cDoc),
    'txt': (icon: Icons.article_outlined, color: Color(0xFF888888)),
    'pdf': (icon: Icons.picture_as_pdf, color: Color(0xFFE53935)),
    'rst': (icon: Icons.description, color: _cDoc),

    // Images
    'png': (icon: Icons.image_outlined, color: _cImage),
    'jpg': (icon: Icons.image_outlined, color: _cImage),
    'jpeg': (icon: Icons.image_outlined, color: _cImage),
    'gif': (icon: Icons.image_outlined, color: _cImage),
    'webp': (icon: Icons.image_outlined, color: _cImage),
    'avif': (icon: Icons.image_outlined, color: _cImage),
    'svg': (icon: Icons.image, color: _cSvg),
    'ico': (icon: Icons.image, color: _cSvg),

    // Fonts
    'ttf': (icon: Icons.font_download_outlined, color: _cFont),
    'otf': (icon: Icons.font_download_outlined, color: _cFont),
    'woff': (icon: Icons.font_download_outlined, color: _cFont),
    'woff2': (icon: Icons.font_download_outlined, color: _cFont),

    // Archives
    'zip': (icon: Icons.folder_zip_outlined, color: _cZip),
    'tar': (icon: Icons.folder_zip_outlined, color: _cZip),
    'gz': (icon: Icons.folder_zip_outlined, color: _cZip),
    'bz2': (icon: Icons.folder_zip_outlined, color: _cZip),
    'xz': (icon: Icons.folder_zip_outlined, color: _cZip),
    'rar': (icon: Icons.folder_zip_outlined, color: _cZip),
    '7z': (icon: Icons.folder_zip_outlined, color: _cZip),

    // Locks / Package manifests / Git / Docker / SQL
    'lock': (icon: Icons.lock_outline, color: Color(0xFFBDBDBD)),
    'pubspec': (icon: Icons.flutter_dash, color: _cFlutter),
    'gitignore': (icon: Icons.merge, color: _cGit),
    'gitattributes': (icon: Icons.merge, color: _cGit),
    'gitmodules': (icon: Icons.merge, color: _cGit),
    'dockerfile': (icon: Icons.dns_outlined, color: _cDocker),
    'sql': (icon: Icons.storage, color: Color(0xFF336791)),
  };

  static ({IconData icon, Color color}) forPath(String path) {
    final name = path.split('/').last.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    return _fileTypes[ext] ?? _byName(name);
  }

  static ({IconData icon, Color color}) _byName(String name) {
    if (name == 'dockerfile') {
      return (icon: Icons.dns_outlined, color: _cDocker);
    }
    if (name.startsWith('.')) {
      return (icon: Icons.settings_outlined, color: const Color(0xFF777777));
    }
    return (
      icon: Icons.insert_drive_file_outlined,
      color: const Color(0xFF90A4AE),
    );
  }

  static const _highlightLanguages = <String, String>{
    'dart': 'dart',
    'js': 'javascript',
    'mjs': 'javascript',
    'ts': 'typescript',
    'jsx': 'xml', // use xml as fallback
    'tsx': 'xml', // use xml as fallback
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

  /// Maps extension to highlight.js language identifier.
  static String? languageFor(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name == '.env' || name.startsWith('.env.')) return 'dotenv';
    final ext = path.split('.').last.toLowerCase();
    return _highlightLanguages[ext];
  }

  static bool isDirectory(String path) => !path.contains('.');
}
