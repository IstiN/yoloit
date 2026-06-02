import 'package:flutter/material.dart';

/// Maps file extensions to Material icons and accent colors.
class FileTypeUtils {
  const FileTypeUtils._();

  static ({IconData icon, Color color}) forPath(String path) {
    final name = path.split('/').last.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';

    return switch (ext) {
      // Dart / Flutter
      'dart' => (icon: Icons.flutter_dash, color: const Color(0xFF54C5F8)),

      // Web
      'html' || 'htm' => (icon: Icons.html, color: const Color(0xFFE34C26)),
      'css' => (icon: Icons.css, color: const Color(0xFF1572B6)),
      'js' ||
      'mjs' ||
      'cjs' => (icon: Icons.javascript, color: const Color(0xFFF7DF1E)),
      'ts' || 'tsx' => (icon: Icons.code, color: const Color(0xFF3178C6)),
      'jsx' => (icon: Icons.code, color: const Color(0xFF61DAFB)),
      'vue' => (icon: Icons.code, color: const Color(0xFF42B883)),
      'svelte' => (icon: Icons.code, color: const Color(0xFFFF3E00)),

      // Python
      'py' ||
      'pyi' ||
      'pyw' => (icon: Icons.code, color: const Color(0xFF3776AB)),

      // JVM
      'java' => (icon: Icons.coffee, color: const Color(0xFFB07219)),
      'kt' || 'kts' => (icon: Icons.code, color: const Color(0xFF7F52FF)),
      'groovy' => (icon: Icons.code, color: const Color(0xFF4298B8)),

      // C family
      'c' || 'h' => (icon: Icons.code, color: const Color(0xFF555555)),
      'cpp' ||
      'cc' ||
      'cxx' ||
      'hpp' => (icon: Icons.code, color: const Color(0xFF004482)),
      'cs' => (icon: Icons.code, color: const Color(0xFF9B4F96)),

      // Swift / ObjC
      'swift' => (icon: Icons.code, color: const Color(0xFFF05138)),
      'm' || 'mm' => (icon: Icons.code, color: const Color(0xFF438EFF)),

      // Go
      'go' => (icon: Icons.code, color: const Color(0xFF00ADD8)),

      // Rust
      'rs' => (icon: Icons.code, color: const Color(0xFFDEA584)),

      // Ruby
      'rb' || 'erb' => (icon: Icons.code, color: const Color(0xFFCC342D)),

      // PHP
      'php' => (icon: Icons.code, color: const Color(0xFF777BB4)),

      // Shell
      'sh' ||
      'bash' ||
      'zsh' ||
      'fish' => (icon: Icons.terminal, color: const Color(0xFF4EAA25)),
      'ps1' || 'psm1' => (icon: Icons.terminal, color: const Color(0xFF012456)),

      // Data / Config
      'json' ||
      'jsonc' => (icon: Icons.data_object, color: const Color(0xFFCBCB41)),
      'yaml' || 'yml' => (
        icon: Icons.settings_input_component,
        color: const Color(0xFFCB171E),
      ),
      'toml' => (icon: Icons.settings, color: const Color(0xFF9C4121)),
      'xml' => (icon: Icons.code, color: const Color(0xFFF1672C)),
      'env' => (icon: Icons.lock_outline, color: const Color(0xFFECD53F)),
      'ini' ||
      'cfg' ||
      'conf' => (icon: Icons.tune, color: const Color(0xFF999999)),
      'properties' => (icon: Icons.tune, color: const Color(0xFF999999)),

      // Markdown / Docs
      'md' ||
      'mdx' ||
      'markdown' => (icon: Icons.description, color: const Color(0xFF519ABA)),
      'txt' => (icon: Icons.article_outlined, color: const Color(0xFF888888)),
      'pdf' => (icon: Icons.picture_as_pdf, color: const Color(0xFFE53935)),
      'rst' => (icon: Icons.description, color: const Color(0xFF519ABA)),

      // Images
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'webp' ||
      'avif' => (icon: Icons.image_outlined, color: const Color(0xFF26A69A)),
      'svg' => (icon: Icons.image, color: const Color(0xFFFF9800)),
      'ico' => (icon: Icons.image, color: const Color(0xFFFF9800)),

      // Fonts
      'ttf' || 'otf' || 'woff' || 'woff2' => (
        icon: Icons.font_download_outlined,
        color: const Color(0xFF9575CD),
      ),

      // Archives
      'zip' ||
      'tar' ||
      'gz' ||
      'bz2' ||
      'xz' ||
      'rar' ||
      '7z' => (icon: Icons.folder_zip_outlined, color: const Color(0xFFFFCA28)),

      // Locks / Package manifests
      'lock' => (icon: Icons.lock_outline, color: const Color(0xFFBDBDBD)),
      'pubspec' => (icon: Icons.flutter_dash, color: const Color(0xFF54C5F8)),

      // Git
      'gitignore' ||
      'gitattributes' ||
      'gitmodules' => (icon: Icons.merge, color: const Color(0xFFF05133)),

      // Dockerfile
      'dockerfile' => (
        icon: Icons.dns_outlined,
        color: const Color(0xFF2496ED),
      ),

      // SQL
      'sql' => (icon: Icons.storage, color: const Color(0xFF336791)),

      // Default
      _ => _byName(name),
    };
  }

  static ({IconData icon, Color color}) _byName(String name) {
    if (name == 'dockerfile') {
      return (icon: Icons.dns_outlined, color: const Color(0xFF2496ED));
    }
    if (name.startsWith('.')) {
      return (icon: Icons.settings_outlined, color: const Color(0xFF777777));
    }
    return (
      icon: Icons.insert_drive_file_outlined,
      color: const Color(0xFF90A4AE),
    );
  }

  /// Maps extension to highlight.js language identifier.
  static String? languageFor(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name == '.env' || name.startsWith('.env.')) return 'dotenv';
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => 'dart',
      'js' || 'mjs' => 'javascript',
      'ts' => 'typescript',
      'jsx' || 'tsx' => 'xml', // use xml as fallback
      'py' => 'python',
      'java' => 'java',
      'kt' => 'kotlin',
      'go' => 'go',
      'rs' => 'rust',
      'rb' => 'ruby',
      'php' => 'php',
      'sh' || 'bash' || 'zsh' => 'bash',
      'c' || 'h' => 'c',
      'cpp' || 'cc' || 'cxx' => 'cpp',
      'cs' => 'csharp',
      'swift' => 'swift',
      'html' || 'htm' => 'xml',
      'css' => 'css',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'env' => 'dotenv',
      'xml' => 'xml',
      'svg' => 'xml',
      'sql' => 'sql',
      'md' || 'markdown' => 'markdown',
      _ => null,
    };
  }

  static bool isDirectory(String path) => !path.contains('.');
}
