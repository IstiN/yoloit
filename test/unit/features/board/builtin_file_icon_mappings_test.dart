import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/files_plugin_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin_vm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codeExtensions = [
    'dart',
    'py',
    'js',
    'ts',
    'java',
    'kt',
    'swift',
    'go',
    'rs',
    'c',
    'cpp',
    'h',
    'cs',
  ];
  const dataExtensions = ['json', 'yaml', 'yml', 'xml', 'toml', 'ini'];
  const documentExtensions = ['md', 'txt', 'rtf'];
  const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'svg', 'webp'];
  const videoExtensions = ['mp4', 'mov', 'avi', 'mkv'];
  const audioExtensions = ['mp3', 'wav', 'flac', 'aac'];
  const archiveExtensions = ['zip', 'tar', 'gz', 'rar', '7z'];

  test('file tree preserves every file icon classification', () {
    void expectFiles(List<String> extensions, IconData icon) {
      for (final extension in extensions) {
        expect(
          debugFileTreeIconForFile('sample.$extension'),
          icon,
          reason: extension,
        );
      }
    }

    expectFiles(codeExtensions, Icons.code_outlined);
    expectFiles(dataExtensions, Icons.data_object_outlined);
    expectFiles(documentExtensions, Icons.article_outlined);
    expectFiles(imageExtensions, Icons.image_outlined);
    expectFiles(videoExtensions, Icons.videocam_outlined);
    expectFiles(audioExtensions, Icons.audiotrack_outlined);
    expectFiles(['pdf'], Icons.picture_as_pdf_outlined);
    expectFiles(archiveExtensions, Icons.folder_zip_outlined);
    expect(debugFileTreeIconForFile('SAMPLE.DART'), Icons.code_outlined);

    for (final name in ['README', '.unknown', 'file.unknown']) {
      expect(
        debugFileTreeIconForFile(name),
        Icons.insert_drive_file_outlined,
        reason: name,
      );
    }
  });

  test('files panel preserves every extension icon classification', () {
    void expectExtensions(List<String> extensions, IconData icon) {
      for (final extension in extensions) {
        expect(
          debugFilesIconForExtension(extension),
          icon,
          reason: extension,
        );
      }
    }

    expectExtensions(codeExtensions, Icons.code_outlined);
    expectExtensions(dataExtensions, Icons.data_object_outlined);
    expectExtensions(documentExtensions, Icons.article_outlined);
    expectExtensions(imageExtensions, Icons.image_outlined);
    expectExtensions(videoExtensions, Icons.videocam_outlined);
    expectExtensions(audioExtensions, Icons.audiotrack_outlined);
    expectExtensions(['pdf'], Icons.picture_as_pdf_outlined);
    expectExtensions(archiveExtensions, Icons.folder_zip_outlined);
    expect(debugFilesIconForExtension('DART'), Icons.code_outlined);
    expect(debugFilesIconForExtension(''), Icons.folder_outlined);
    expect(
      debugFilesIconForExtension('unknown'),
      Icons.insert_drive_file_outlined,
    );
  });
}
