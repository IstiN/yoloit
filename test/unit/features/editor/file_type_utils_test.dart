import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/editor/utils/file_type_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileTypeUtils.forPath', () {
    test('returns Dart icon for .dart files', () {
      final result = FileTypeUtils.forPath('lib/main.dart');
      expect(result.icon, Icons.flutter_dash);
      expect(result.color, const Color(0xFF54C5F8));
    });

    test('returns HTML icon for .html files', () {
      final result = FileTypeUtils.forPath('index.html');
      expect(result.icon, Icons.html);
      expect(result.color, const Color(0xFFE34C26));
    });

    test('returns JS icon for .js files', () {
      final result = FileTypeUtils.forPath('app.js');
      expect(result.icon, Icons.javascript);
      expect(result.color, const Color(0xFFF7DF1E));
    });

    test('returns TS icon for .ts files', () {
      final result = FileTypeUtils.forPath('index.ts');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF3178C6));
    });

    test('returns Python icon for .py files', () {
      final result = FileTypeUtils.forPath('script.py');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF3776AB));
    });

    test('returns Java icon for .java files', () {
      final result = FileTypeUtils.forPath('Main.java');
      expect(result.icon, Icons.coffee);
      expect(result.color, const Color(0xFFB07219));
    });

    test('returns Kotlin icon for .kt files', () {
      final result = FileTypeUtils.forPath('App.kt');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF7F52FF));
    });

    test('returns C icon for .c files', () {
      final result = FileTypeUtils.forPath('main.c');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF555555));
    });

    test('returns C++ icon for .cpp files', () {
      final result = FileTypeUtils.forPath('main.cpp');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF004482));
    });

    test('returns Go icon for .go files', () {
      final result = FileTypeUtils.forPath('main.go');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF00ADD8));
    });

    test('returns Rust icon for .rs files', () {
      final result = FileTypeUtils.forPath('lib.rs');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFFDEA584));
    });

    test('returns Ruby icon for .rb files', () {
      final result = FileTypeUtils.forPath('Gemfile.rb');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFFCC342D));
    });

    test('returns PHP icon for .php files', () {
      final result = FileTypeUtils.forPath('index.php');
      expect(result.icon, Icons.code);
      expect(result.color, const Color(0xFF777BB4));
    });

    test('returns Shell icon for .sh files', () {
      final result = FileTypeUtils.forPath('deploy.sh');
      expect(result.icon, Icons.terminal);
      expect(result.color, const Color(0xFF4EAA25));
    });

    test('returns JSON icon for .json files', () {
      final result = FileTypeUtils.forPath('package.json');
      expect(result.icon, Icons.data_object);
      expect(result.color, const Color(0xFFCBCB41));
    });

    test('returns YAML icon for .yaml files', () {
      final result = FileTypeUtils.forPath('config.yaml');
      expect(result.icon, Icons.settings_input_component);
      expect(result.color, const Color(0xFFCB171E));
    });

    test('returns Markdown icon for .md files', () {
      final result = FileTypeUtils.forPath('README.md');
      expect(result.icon, Icons.description);
      expect(result.color, const Color(0xFF519ABA));
    });

    test('returns PDF icon for .pdf files', () {
      final result = FileTypeUtils.forPath('doc.pdf');
      expect(result.icon, Icons.picture_as_pdf);
      expect(result.color, const Color(0xFFE53935));
    });

    test('returns Image icon for .png files', () {
      final result = FileTypeUtils.forPath('image.png');
      expect(result.icon, Icons.image_outlined);
      expect(result.color, const Color(0xFF26A69A));
    });

    test('returns SVG icon for .svg files', () {
      final result = FileTypeUtils.forPath('icon.svg');
      expect(result.icon, Icons.image);
      expect(result.color, const Color(0xFFFF9800));
    });

    test('returns Font icon for .ttf files', () {
      final result = FileTypeUtils.forPath('font.ttf');
      expect(result.icon, Icons.font_download_outlined);
      expect(result.color, const Color(0xFF9575CD));
    });

    test('returns Archive icon for .zip files', () {
      final result = FileTypeUtils.forPath('archive.zip');
      expect(result.icon, Icons.folder_zip_outlined);
      expect(result.color, const Color(0xFFFFCA28));
    });

    test('returns Lock icon for .lock files', () {
      final result = FileTypeUtils.forPath('pubspec.lock');
      expect(result.icon, Icons.lock_outline);
      expect(result.color, const Color(0xFFBDBDBD));
    });

    test('returns Git icon for .gitignore files', () {
      final result = FileTypeUtils.forPath('.gitignore');
      expect(result.icon, Icons.merge);
      expect(result.color, const Color(0xFFF05133));
    });

    test('returns Docker icon for dockerfile', () {
      final result = FileTypeUtils.forPath('Dockerfile');
      expect(result.icon, Icons.dns_outlined);
      expect(result.color, const Color(0xFF2496ED));
    });

    test('returns SQL icon for .sql files', () {
      final result = FileTypeUtils.forPath('schema.sql');
      expect(result.icon, Icons.storage);
      expect(result.color, const Color(0xFF336791));
    });

    test('returns default icon for unknown extensions', () {
      final result = FileTypeUtils.forPath('file.unknown');
      expect(result.icon, Icons.insert_drive_file_outlined);
      expect(result.color, const Color(0xFF90A4AE));
    });

    test('returns env icon for .env files', () {
      final result = FileTypeUtils.forPath('.env');
      expect(result.icon, Icons.lock_outline);
      expect(result.color, const Color(0xFFECD53F));
    });

    test('is case insensitive', () {
      final lower = FileTypeUtils.forPath('main.dart');
      final upper = FileTypeUtils.forPath('MAIN.DART');
      expect(lower.icon, upper.icon);
      expect(lower.color, upper.color);
    });
  });

  group('FileTypeUtils.languageFor', () {
    test('returns dart for .dart', () {
      expect(FileTypeUtils.languageFor('main.dart'), 'dart');
    });

    test('returns javascript for .js', () {
      expect(FileTypeUtils.languageFor('app.js'), 'javascript');
    });

    test('returns typescript for .ts', () {
      expect(FileTypeUtils.languageFor('index.ts'), 'typescript');
    });

    test('returns python for .py', () {
      expect(FileTypeUtils.languageFor('script.py'), 'python');
    });

    test('returns java for .java', () {
      expect(FileTypeUtils.languageFor('Main.java'), 'java');
    });

    test('returns kotlin for .kt', () {
      expect(FileTypeUtils.languageFor('App.kt'), 'kotlin');
    });

    test('returns go for .go', () {
      expect(FileTypeUtils.languageFor('main.go'), 'go');
    });

    test('returns rust for .rs', () {
      expect(FileTypeUtils.languageFor('lib.rs'), 'rust');
    });

    test('returns ruby for .rb', () {
      expect(FileTypeUtils.languageFor('Gemfile.rb'), 'ruby');
    });

    test('returns php for .php', () {
      expect(FileTypeUtils.languageFor('index.php'), 'php');
    });

    test('returns bash for .sh', () {
      expect(FileTypeUtils.languageFor('deploy.sh'), 'bash');
    });

    test('returns c for .c', () {
      expect(FileTypeUtils.languageFor('main.c'), 'c');
    });

    test('returns cpp for .cpp', () {
      expect(FileTypeUtils.languageFor('main.cpp'), 'cpp');
    });

    test('returns csharp for .cs', () {
      expect(FileTypeUtils.languageFor('Program.cs'), 'csharp');
    });

    test('returns swift for .swift', () {
      expect(FileTypeUtils.languageFor('App.swift'), 'swift');
    });

    test('returns xml for .html', () {
      expect(FileTypeUtils.languageFor('index.html'), 'xml');
    });

    test('returns css for .css', () {
      expect(FileTypeUtils.languageFor('style.css'), 'css');
    });

    test('returns json for .json', () {
      expect(FileTypeUtils.languageFor('package.json'), 'json');
    });

    test('returns yaml for .yaml', () {
      expect(FileTypeUtils.languageFor('config.yaml'), 'yaml');
    });

    test('returns sql for .sql', () {
      expect(FileTypeUtils.languageFor('schema.sql'), 'sql');
    });

    test('returns markdown for .md', () {
      expect(FileTypeUtils.languageFor('README.md'), 'markdown');
    });

    test('returns dotenv for .env', () {
      expect(FileTypeUtils.languageFor('.env'), 'dotenv');
    });

    test('returns dotenv for .env.local', () {
      expect(FileTypeUtils.languageFor('.env.local'), 'dotenv');
    });

    test('returns null for unknown extension', () {
      expect(FileTypeUtils.languageFor('file.xyz'), isNull);
    });
  });

  group('FileTypeUtils.isDirectory', () {
    test('returns true for paths without dot', () {
      expect(FileTypeUtils.isDirectory('lib/features'), true);
    });

    test('returns false for files with extension', () {
      expect(FileTypeUtils.isDirectory('lib/main.dart'), false);
    });

    test('returns false for dotfiles (contains dot)', () {
      expect(FileTypeUtils.isDirectory('.git'), false);
    });

    test('returns true for directory without dots', () {
      expect(FileTypeUtils.isDirectory('src'), true);
    });
  });
}
